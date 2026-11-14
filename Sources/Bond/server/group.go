// A group: the legs of one Mac (one client id) and the streams they carry. Everything of a group is guarded by g.mu;
// the waits (a full window, every leg at its in-flight cap, an empty inbox) are sync.Conds on that same mutex.
package main

import (
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"sort"
	"sync"
	"syscall"
	"time"
)

const (
	window         = 4 << 20   // unacknowledged bytes per stream and direction
	streamAckEvery = 256 << 10 // a stream ACK at least every 256 KB delivered (else on the 50 ms tick)
	legAckEvery    = 32 << 10  // a leg ACK at least every 32 KB received (else on the 50 ms tick)
	tick           = 50 * time.Millisecond
	legSilence     = 3.0 // seconds without a record: the leg is dead
	streamIdle     = 10 * time.Minute
	groupLinger    = 60 * time.Second
	maxStreams     = 1024
	maxLegs        = 64
	minCap         = 64 << 10
	dialTimeout    = 10 * time.Second
)

var epoch = time.Now()

func mono() float64 { return time.Since(epoch).Seconds() }

type pending struct {
	seq    uint32
	enc    []byte
	leg    *leg
	legEnd uint64 // the leg's byte count after this frame: received when the leg's ACK reaches it
}

type leg struct {
	id     int
	conn   net.Conn
	g      *group
	tx, rx *aeadDir
	remote string
	wcond  *sync.Cond

	ctlq, dataq                [][]byte
	sent, acked, recv, rAcked  uint64 // sequenced bytes: queued here / acked by the Mac; received here / acked to the Mac
	rttMin, rttMinAt, rate     float64
	sampleAt                   float64
	sampleAcked                uint64
	busyAll                    bool // backlogged since the last rate sample
	capped, dead, gotPong      bool
	lastHeard, lastPing, start float64
	pingID                     uint32
}

type stream struct {
	id   uint32
	g    *group
	cond *sync.Cond
	conn *net.TCPConn

	nextSeq, peerAck uint32
	unacked          map[uint32]*pending
	unackedBytes     int
	sentBytes        int // v67: a stream's first 64 KB may use twice a leg's cap
	expect           uint32
	ooo              map[uint32]frame
	inbox            []frame
	delivered        uint32
	ackSent          uint32
	ackBytes         int
	ackForce         bool
	finSent, finRecv bool
	failed, done     bool
	target           string
	born             time.Time
	lastActive       time.Time
}

type group struct {
	srv        *server
	id         [16]byte
	name       string
	mu         sync.Mutex
	cond       *sync.Cond
	legs       []*leg
	nextLeg    int
	streams    map[uint32]*stream
	closed     map[uint32]time.Time
	emptySince time.Time
	gone       bool
	up, down   int64 // bytes Mac -> destinations, destinations -> Mac
	opened     int
	lastReport time.Time
}

func newGroup(s *server, id [16]byte) *group {
	g := &group{srv: s, id: id, name: hex.EncodeToString(id[:4]), streams: map[uint32]*stream{}, closed: map[uint32]time.Time{},
		emptySince: time.Now(), lastReport: time.Now()}
	g.cond = sync.NewCond(&g.mu)
	log.Printf("BOND group %s: new", g.name)
	return g
}

func (g *group) addLeg(l *leg) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.gone || len(g.legs) >= maxLegs {
		return false
	}
	now := mono()
	l.wcond = sync.NewCond(&g.mu)
	l.id = g.nextLeg
	g.nextLeg++
	l.lastHeard, l.start, l.sampleAt = now, now, now
	l.rate, l.rttMin, l.busyAll = 2.5e6, 0.05, true
	l.ctlq = append(l.ctlq, frame{typ: fWelcome}.encode()) // the first record of the leg
	g.legs = append(g.legs, l)
	g.cond.Broadcast()
	log.Printf("BOND group %s: leg %d from %s joined (%d legs)", g.name, l.id, l.remote, len(g.legs))
	return true
}

// MARK: the legs

func (l *leg) writer() {
	g := l.g
	buf := make([]byte, 0, 1<<20)
	for {
		g.mu.Lock()
		for !l.dead && len(l.ctlq) == 0 && len(l.dataq) == 0 {
			l.wcond.Wait()
		}
		if l.dead {
			g.mu.Unlock()
			return
		}
		batch := append(l.ctlq, l.dataq...)
		l.ctlq, l.dataq = nil, nil
		g.mu.Unlock()
		buf = buf[:0]
		for _, p := range batch {
			buf = l.tx.sealRecord(buf, p)
		}
		l.conn.SetWriteDeadline(time.Now().Add(20 * time.Second))
		if _, err := l.conn.Write(buf); err != nil {
			g.mu.Lock()
			g.killLeg(l, "write failed")
			g.mu.Unlock()
			return
		}
	}
}

func (l *leg) reader() {
	g := l.g
	hdr := make([]byte, 2)
	rec := make([]byte, maxRecord)
	why := "closed by the Mac"
	for {
		if _, err := io.ReadFull(l.conn, hdr); err != nil {
			break
		}
		n := int(binary.BigEndian.Uint16(hdr))
		if n < hdrLen+tagLen || n > maxRecord {
			why = "bad record length"
			break
		}
		if _, err := io.ReadFull(l.conn, rec[:n]); err != nil {
			break
		}
		plain, err := l.rx.open(rec[:n])
		if err != nil {
			why = "a record did not decrypt"
			break
		}
		f, err := decodeFrame(plain)
		if err != nil {
			why = "bad frame"
			break
		}
		g.mu.Lock()
		g.onFrame(l, f)
		g.mu.Unlock()
	}
	g.mu.Lock()
	g.killLeg(l, why)
	g.mu.Unlock()
}

// killLeg (under g.mu): the leg is closed and every frame it carried that the Mac has not confirmed goes out again on
// the other legs.
func (g *group) killLeg(l *leg, why string) {
	if l.dead {
		return
	}
	l.dead = true
	l.conn.Close()
	for i, x := range g.legs {
		if x == l {
			g.legs = append(g.legs[:i], g.legs[i+1:]...)
			break
		}
	}
	if len(g.legs) == 0 {
		g.emptySince = time.Now()
	}
	type redo struct {
		s *stream
		p *pending
	}
	var list []redo
	for _, s := range g.streams {
		if s.done {
			continue
		}
		for _, p := range s.unacked {
			if p.leg == l && p.legEnd > l.acked {
				list = append(list, redo{s, p})
			}
		}
	}
	sort.Slice(list, func(i, j int) bool {
		if list[i].s.id != list[j].s.id {
			return list[i].s.id < list[j].s.id
		}
		return list[i].p.seq < list[j].p.seq
	})
	l.wcond.Broadcast()
	g.cond.Broadcast()
	log.Printf("BOND group %s: leg %d (%s) down: %s; %d frames resent, %d legs left", g.name, l.id, l.remote, why, len(list), len(g.legs))
	if len(list) == 0 {
		return
	}
	go func() {
		g.mu.Lock()
		defer g.mu.Unlock()
		for _, r := range list {
			if r.s.done || r.p.leg != l || r.s.unacked[r.p.seq] != r.p {
				continue
			}
			if !g.place(r.s, r.p) {
				return
			}
		}
	}()
}

// pick (under g.mu): the live leg where these n bytes would arrive first, RTT/2 + queued/rate, among those under their
// in-flight cap (about 2 x rate x RTT plus the ACK interval, at least 64 KB). nil: every leg is full (or none is up).
// urgent: a young stream (its first 64 KB, a handshake or a small answer) may use up to twice the cap, so it does not wait
// behind the bulk of the other streams.
func (g *group) pick(n int, urgent bool) *leg {
	var best *leg
	bt := 0.0
	for _, l := range g.legs {
		if l.dead {
			continue
		}
		infl := float64(l.sent - l.acked)
		limit := max(minCap, l.rate*(2*l.rttMin+0.05))
		if infl > 0 && infl+float64(n) > limit && !(urgent && infl+float64(n) <= 2*limit) {
			l.capped = true
			continue
		}
		t := l.rttMin/2 + (infl+float64(n))/l.rate
		if best == nil || t < bt {
			best, bt = l, t
		}
	}
	return best
}

// place (under g.mu, may wait): puts a sequenced frame on a leg.
func (g *group) place(s *stream, p *pending) bool {
	n := len(p.enc)
	for {
		if g.gone || s.done {
			return false
		}
		if l := g.pick(n, s.sentBytes <= 65536); l != nil {
			l.dataq = append(l.dataq, p.enc)
			l.sent += uint64(n)
			p.leg, p.legEnd = l, l.sent
			l.wcond.Signal()
			return true
		}
		g.cond.Wait()
	}
}

func (g *group) ctl(l *leg, f frame) {
	if l == nil || l.dead {
		return
	}
	l.ctlq = append(l.ctlq, f.encode())
	l.wcond.Signal()
}

func (g *group) bestLeg() *leg {
	var best *leg
	for _, l := range g.legs {
		if !l.dead && (best == nil || l.rttMin < best.rttMin) {
			best = l
		}
	}
	return best
}

func (g *group) sendLegAck(l *leg) {
	p := make([]byte, 8)
	binary.BigEndian.PutUint64(p, l.recv)
	g.ctl(l, frame{typ: fAck, payload: p})
	l.rAcked = l.recv
}

func (g *group) sendStreamAck(s *stream) {
	l := g.bestLeg()
	if l == nil {
		return
	}
	g.ctl(l, frame{typ: fAck, stream: s.id, seq: s.delivered})
	s.ackSent, s.ackBytes, s.ackForce = s.delivered, 0, false
}

// A leg ACK: what the Mac has received on this leg. It frees in-flight room and measures the leg's rate.
func (g *group) legAck(l *leg, v uint64) {
	if v > l.acked && v <= l.sent {
		l.acked = v
	}
	// the delivery over >= 250 ms (and 2 RTT), smoothed; it follows a sample down only when the leg was backlogged the whole
	// time (found full between every two ACKs). A best-100-ms maximum believed a phone's adb bursts (v66, live 14.11.2026).
	if !l.capped {
		l.busyAll = false
	}
	l.capped = false
	now := mono()
	if dt := now - l.sampleAt; dt >= max(0.25, 2*l.rttMin) {
		sample := float64(l.acked-l.sampleAcked) / dt
		if l.busyAll {
			l.rate = max(16384, 0.6*l.rate+0.4*sample)
		} else if sample > l.rate {
			l.rate = 0.6*l.rate + 0.4*sample
		}
		l.busyAll, l.sampleAt, l.sampleAcked = true, now, l.acked
	}
	g.cond.Broadcast()
}

func (g *group) onFrame(l *leg, f frame) {
	now := mono()
	l.lastHeard = now
	switch f.typ {
	case fPing:
		if len(f.payload) >= 8 { // the echo, and our rate for this leg (v67: shown in the Mac's /status)
			p := make([]byte, 16)
			copy(p, f.payload[:8])
			binary.BigEndian.PutUint64(p[8:], uint64(l.rate))
			g.ctl(l, frame{typ: fPong, seq: f.seq, payload: p})
		}
	case fPong:
		if len(f.payload) >= 8 {
			rtt := max(now-float64(binary.BigEndian.Uint64(f.payload[:8]))/1e9, 0.0005)
			if !l.gotPong || rtt < l.rttMin { // the lowest seen: a PING waits behind the leg's own queue
				l.rttMin, l.rttMinAt = rtt, now
			}
			l.gotPong = true
		}
	case fAck:
		if f.stream == 0 {
			if len(f.payload) == 8 {
				g.legAck(l, binary.BigEndian.Uint64(f.payload))
			}
		} else if s := g.streams[f.stream]; s != nil {
			g.streamAck(s, f.seq)
		}
	case fRst:
		if s := g.streams[f.stream]; s != nil {
			g.finish(s, false)
		}
	case fOpen, fOpenOK, fOpenFail, fData, fFin:
		l.recv += uint64(f.size())
		if l.recv-l.rAcked >= legAckEvery {
			g.sendLegAck(l)
		}
		g.onSeq(l, f)
	}
}

// MARK: the streams

func (g *group) onSeq(l *leg, f frame) {
	s := g.streams[f.stream]
	if s == nil {
		if _, was := g.closed[f.stream]; was {
			g.ctl(l, frame{typ: fAck, stream: f.stream, seq: f.seq + 1}) // a late copy: it has all it needs
			return
		}
		// v67: any first frame makes the stream: with the Mac's optimistic OPEN its first DATA can come on a faster leg
		// than the OPEN (it waits in ooo). A stream whose OPEN never comes (a group made again) is reset after 10 s.
		if len(g.streams) >= maxStreams {
			g.closed[f.stream] = time.Now()
			g.ctl(l, frame{typ: fRst, stream: f.stream})
			log.Printf("BOND group %s: %d streams open, a new one refused", g.name, maxStreams)
			return
		}
		s = &stream{id: f.stream, g: g, unacked: map[uint32]*pending{}, ooo: map[uint32]frame{}, lastActive: time.Now(), born: time.Now()}
		s.cond = sync.NewCond(&g.mu)
		g.streams[f.stream] = s
		go s.deliver()
	}
	s.lastActive = time.Now()
	switch {
	case f.seq < s.expect:
		s.ackForce = true // a copy: the Mac lost our ACK with its leg
	case f.seq == s.expect:
		s.inbox = append(s.inbox, f)
		s.expect++
		for {
			n, ok := s.ooo[s.expect]
			if !ok {
				break
			}
			delete(s.ooo, s.expect)
			s.inbox = append(s.inbox, n)
			s.expect++
		}
		s.cond.Signal()
	default:
		if _, dup := s.ooo[f.seq]; dup {
			s.ackForce = true
		} else {
			s.ooo[f.seq] = f
		}
	}
}

// sendSeq (under g.mu, may wait for the window and a leg).
func (g *group) sendSeq(s *stream, typ byte, payload []byte) bool {
	f := frame{typ: typ, stream: s.id, payload: payload}
	n := f.size()
	for !s.done && !g.gone && s.unackedBytes > 0 && s.unackedBytes+n > window {
		g.cond.Wait()
	}
	if s.done || g.gone {
		return false
	}
	f.seq = s.nextSeq
	s.nextSeq++
	p := &pending{seq: f.seq, enc: f.encode()}
	s.unacked[f.seq] = p
	s.unackedBytes += n
	s.sentBytes += n
	switch typ {
	case fFin:
		s.finSent = true
	case fData:
		g.down += int64(len(payload))
		s.lastActive = time.Now()
	}
	return g.place(s, p)
}

func (g *group) streamAck(s *stream, v uint32) {
	if v > s.nextSeq {
		return
	}
	for s.peerAck < v {
		if p := s.unacked[s.peerAck]; p != nil {
			s.unackedBytes -= len(p.enc)
			delete(s.unacked, s.peerAck)
		}
		s.peerAck++
	}
	g.cond.Broadcast()
	g.checkDone(s)
}

func (g *group) checkDone(s *stream) {
	if s.done || s.peerAck != s.nextSeq {
		return
	}
	if (s.finSent && s.finRecv && len(s.inbox) == 0) || s.failed {
		g.finish(s, false)
	}
}

// finish (under g.mu): the stream ends; rst tells the Mac (on every leg, best effort). It leaves the table at the next
// tick, after its last ACK went out.
func (g *group) finish(s *stream, rst bool) {
	if s.done {
		return
	}
	s.done = true
	if s.conn != nil {
		s.conn.Close()
	}
	if rst {
		for _, l := range g.legs {
			g.ctl(l, frame{typ: fRst, stream: s.id})
		}
	}
	s.cond.Broadcast()
	g.cond.Broadcast()
}

// deliver: the stream's frames in order. OPEN dials the destination; DATA is written to it; FIN half-closes it.
func (s *stream) deliver() {
	g := s.g
	for {
		g.mu.Lock()
		for len(s.inbox) == 0 && !s.done {
			s.cond.Wait()
		}
		if s.done {
			g.mu.Unlock()
			return
		}
		f := s.inbox[0]
		s.inbox[0] = frame{}
		s.inbox = s.inbox[1:]
		conn := s.conn
		g.mu.Unlock()
		ok := true
		switch f.typ {
		case fOpen:
			s.dial(string(f.payload))
		case fData:
			if conn == nil {
				ok = false
			} else if _, err := conn.Write(f.payload); err != nil {
				ok = false
			}
		case fFin:
			if conn != nil {
				conn.CloseWrite()
			}
		default:
			ok = false
		}
		g.mu.Lock()
		s.delivered++
		s.ackBytes += f.size()
		switch f.typ {
		case fFin:
			s.finRecv = true
		case fData:
			g.up += int64(len(f.payload))
		}
		if !ok {
			g.finish(s, true)
		} else {
			if s.ackBytes >= streamAckEvery {
				g.sendStreamAck(s)
			}
			g.checkDone(s)
		}
		g.mu.Unlock()
	}
}

var errLocal = errors.New("a local address")

// refuseLocal: the relay is for the internet; loopback, private, link-local (the cloud's metadata service) and
// carrier-grade NAT (Tailscale) addresses are refused unless -allow-local.
func refuseLocal(network, address string, _ syscall.RawConn) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return err
	}
	ip := net.ParseIP(host)
	if ip == nil || ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() || ip.IsMulticast() {
		return errLocal
	}
	if v4 := ip.To4(); v4 != nil && v4[0] == 100 && v4[1]&0xC0 == 64 {
		return errLocal
	}
	return nil
}

func (s *stream) dial(target string) {
	g := s.g
	d := net.Dialer{Timeout: dialTimeout}
	if !g.srv.allowLocal {
		d.Control = refuseLocal
	}
	c, err := d.Dial("tcp", target)
	g.mu.Lock()
	defer g.mu.Unlock()
	s.target = target
	if err != nil || s.done {
		if c != nil {
			c.Close()
		}
		if !s.done {
			s.failed = true
			reason := "unreachable"
			if errors.Is(err, errLocal) {
				reason = "local address refused"
			}
			g.sendSeq(s, fOpenFail, []byte(reason))
		}
		return
	}
	s.conn = c.(*net.TCPConn)
	g.opened++
	g.sendSeq(s, fOpenOK, nil)
	go s.readLoop()
}

// readLoop: the destination's bytes become DATA frames; its end, a FIN.
func (s *stream) readLoop() {
	g := s.g
	buf := make([]byte, maxPayload)
	for {
		n, err := s.conn.Read(buf)
		if n > 0 {
			p := append([]byte(nil), buf[:n]...)
			g.mu.Lock()
			ok := g.sendSeq(s, fData, p)
			g.mu.Unlock()
			if !ok {
				return
			}
		}
		if err != nil {
			g.mu.Lock()
			if err == io.EOF {
				g.sendSeq(s, fFin, nil)
				g.checkDone(s)
			} else {
				g.finish(s, true)
			}
			g.mu.Unlock()
			return
		}
	}
}

// MARK: the clock of the group

func (g *group) loop() {
	t := time.NewTicker(tick)
	defer t.Stop()
	for range t.C {
		g.mu.Lock()
		now, wall := mono(), time.Now()
		for _, l := range append([]*leg(nil), g.legs...) {
			if now-l.lastHeard > legSilence {
				g.killLeg(l, "silent for 3 s")
				continue
			}
			if now-l.lastPing >= 1 {
				l.lastPing = now
				l.pingID++
				p := make([]byte, 8)
				binary.BigEndian.PutUint64(p, uint64(now*1e9))
				g.ctl(l, frame{typ: fPing, seq: l.pingID, payload: p})
			}
			if l.recv != l.rAcked {
				g.sendLegAck(l)
			}
		}
		for id, s := range g.streams {
			if s.delivered != s.ackSent || s.ackForce {
				g.sendStreamAck(s)
			}
			if !s.done && s.expect == 0 && wall.Sub(s.born) > 10*time.Second {
				g.finish(s, true) // its OPEN never came
			}
			if !s.done && wall.Sub(s.lastActive) > streamIdle {
				g.finish(s, true)
			}
			if s.done {
				delete(g.streams, id)
				g.closed[id] = wall
			}
		}
		for id, at := range g.closed {
			if wall.Sub(at) > 10*time.Minute {
				delete(g.closed, id)
			}
		}
		if wall.Sub(g.lastReport) >= time.Minute && (g.up > 0 || g.down > 0) {
			legs := ""
			for _, l := range g.legs {
				legs += fmt.Sprintf("; leg %d %s: rtt %.0f ms, rate %.1f Mbit/s, sent %.1f MB", l.id, l.remote, l.rttMin*1000, l.rate*8/1e6, float64(l.sent)/1e6)
			}
			log.Printf("BOND group %s: %d legs, %d streams, %d opened, up %.1f MB, down %.1f MB in total%s", g.name, len(g.legs), len(g.streams), g.opened, float64(g.up)/1e6, float64(g.down)/1e6, legs)
			g.lastReport = wall
		}
		if len(g.legs) == 0 && wall.Sub(g.emptySince) > groupLinger {
			g.gone = true
			for _, s := range g.streams {
				g.finish(s, false)
			}
			g.cond.Broadcast()
			g.mu.Unlock()
			g.srv.drop(g)
			log.Printf("BOND group %s: no leg for 60 s, gone", g.name)
			return
		}
		g.cond.Broadcast()
		g.mu.Unlock()
	}
}
