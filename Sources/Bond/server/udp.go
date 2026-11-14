// UDP through the bond (v74, request 85: "UDP flows (QUIC/HTTP3, WebRTC calls, games, DNS) go through the relay").
//
// A flow is one UDP association of the Mac (one SOCKS5 UDP ASSOCIATE): the relay sends and receives for it from ONE UDP
// socket of its own, like a cone NAT, so QUIC, STUN/ICE and games keep one outside address and port for all their peers.
// Datagrams are unreliable frames (DGRAM 11): not numbered for order, never resent, never waited for; `seq` only lets the
// receiver drop the copies of a redundant flow. Payload: flags u8 (bit 0: redundant, send the replies on two legs too) |
// atyp u8 (1 IPv4, 4 IPv6, 3 name) | address | port u16 | data. DGRAM_CLOSE (12) ends a flow. Timeouts as a NAT:
// 30 s without an answer from outside, 180 s idle once answered. At most 256 flows per group.
package main

import (
	"encoding/binary"
	"errors"
	"log"
	"net"
	"strconv"
	"time"
)

const (
	fDgram      byte = 11
	fDgramClose byte = 12
	maxFlows         = 256
	udpQueueMax      = 256 << 10 // bytes of datagrams waiting on one leg; beyond it a datagram is dropped (UDP)
	flowNew          = 30 * time.Second
	flowEstablished  = 180 * time.Second
)

type dedupe struct {
	max  uint32
	bits uint64
	any  bool
}

// fresh: true the first time this seq is seen (a window of 64).
func (d *dedupe) fresh(s uint32) bool {
	if !d.any {
		d.any, d.max, d.bits = true, s, 1
		return true
	}
	if s > d.max {
		if sh := s - d.max; sh >= 64 {
			d.bits = 1
		} else {
			d.bits = d.bits<<sh | 1
		}
		d.max = s
		return true
	}
	off := d.max - s
	if off >= 64 {
		return false
	}
	m := uint64(1) << off
	if d.bits&m != 0 {
		return false
	}
	d.bits |= m
	return true
}

type uflow struct {
	id                uint32
	conn              *net.UDPConn
	redundant         bool
	seqOut            uint32
	seen              dedupe
	lastOut, lastIn   time.Time
	answered, closed  bool
	bytesUp, bytesDown int64
}

var errLocalUDP = errors.New("local address")

// parseAddr: atyp | address | port at the start of b; the UDP address and the length used.
func parseAddr(b []byte) (*net.UDPAddr, int, error) {
	if len(b) < 1 {
		return nil, 0, errFrame
	}
	switch b[0] {
	case 1:
		if len(b) < 7 {
			return nil, 0, errFrame
		}
		return &net.UDPAddr{IP: net.IP(append([]byte(nil), b[1:5]...)), Port: int(binary.BigEndian.Uint16(b[5:7]))}, 7, nil
	case 4:
		if len(b) < 19 {
			return nil, 0, errFrame
		}
		return &net.UDPAddr{IP: net.IP(append([]byte(nil), b[1:17]...)), Port: int(binary.BigEndian.Uint16(b[17:19]))}, 19, nil
	case 3:
		if len(b) < 2 || len(b) < 2+int(b[1])+2 {
			return nil, 0, errFrame
		}
		n := int(b[1])
		host := string(b[2 : 2+n])
		port := int(binary.BigEndian.Uint16(b[2+n : 4+n]))
		a, err := net.ResolveUDPAddr("udp", net.JoinHostPort(host, strconv.Itoa(port)))
		return a, 4 + n, err
	}
	return nil, 0, errFrame
}

func localIP(ip net.IP) bool {
	if ip == nil || ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() || ip.IsMulticast() || ip.IsLinkLocalMulticast() {
		return true
	}
	v4 := ip.To4()
	return v4 != nil && v4[0] == 100 && v4[1]&0xC0 == 64
}

// onDgram (under g.mu): a datagram from the Mac, sent on out of the flow's socket.
func (g *group) onDgram(f frame) {
	if len(f.payload) < 2 {
		return
	}
	fl := g.flows[f.stream]
	if fl == nil {
		if len(g.flows) >= maxFlows {
			return
		}
		c, err := net.ListenUDP("udp", nil)
		if err != nil {
			return
		}
		fl = &uflow{id: f.stream, conn: c, lastOut: time.Now()}
		g.flows[f.stream] = fl
		go g.flowReader(fl)
	}
	if !fl.seen.fresh(f.seq) {
		return // the second copy of a redundant datagram
	}
	fl.redundant = f.payload[0]&1 != 0
	dst, n, err := parseAddr(f.payload[1:])
	if err != nil || (!g.srv.allowLocal && localIP(dst.IP)) {
		return
	}
	data := f.payload[1+n:]
	fl.lastOut = time.Now()
	fl.bytesUp += int64(len(data))
	g.up += int64(len(data))
	fl.conn.WriteToUDP(data, dst) // never blocks long: a UDP socket
}

func (g *group) flowReader(fl *uflow) {
	buf := make([]byte, 65535)
	for {
		n, from, err := fl.conn.ReadFromUDP(buf)
		if err != nil {
			return
		}
		var hdr []byte
		if v4 := from.IP.To4(); v4 != nil {
			hdr = append([]byte{0, 1}, v4...)
		} else {
			hdr = append([]byte{0, 4}, from.IP.To16()...)
		}
		hdr = binary.BigEndian.AppendUint16(hdr, uint16(from.Port))
		if len(hdr)+n > maxPayload {
			continue // larger than a frame (a jumbo datagram): dropped, as a too small MTU would
		}
		p := append(hdr, buf[:n]...)
		g.mu.Lock()
		if fl.closed {
			g.mu.Unlock()
			return
		}
		fl.lastIn, fl.answered = time.Now(), true
		fl.bytesDown += int64(n)
		g.down += int64(n)
		fl.seqOut++
		g.sendDgram(fl, frame{typ: fDgram, stream: fl.id, seq: fl.seqOut, payload: p})
		g.mu.Unlock()
	}
}

// sendDgram (under g.mu): on the quickest leg with room (and the second quickest too for a redundant flow).
func (g *group) sendDgram(fl *uflow, f frame) {
	enc := f.encode()
	var first, second *leg
	for _, l := range g.legs {
		if l.dead || l.udpBytes+len(enc) > udpQueueMax {
			continue
		}
		if first == nil || l.rttMin < first.rttMin {
			first, second = l, first
		} else if second == nil || l.rttMin < second.rttMin {
			second = l
		}
	}
	for i, l := range []*leg{first, second} {
		if l == nil || (i == 1 && !fl.redundant) {
			continue
		}
		l.udpq = append(l.udpq, enc)
		l.udpBytes += len(enc)
		l.wcond.Signal()
	}
}

func (g *group) closeFlow(id uint32) {
	if fl := g.flows[id]; fl != nil {
		fl.closed = true
		fl.conn.Close()
		delete(g.flows, id)
	}
}

// expireFlows (under g.mu, the tick): NAT-style timeouts.
func (g *group) expireFlows(now time.Time) {
	for id, fl := range g.flows {
		last := fl.lastOut
		if fl.lastIn.After(last) {
			last = fl.lastIn
		}
		limit := flowNew
		if fl.answered {
			limit = flowEstablished
		}
		if now.Sub(last) > limit {
			g.closeFlow(id)
		}
	}
	if len(g.flows) > 0 && now.Sub(g.lastFlowReport) >= time.Minute {
		var up, down int64
		for _, fl := range g.flows {
			up += fl.bytesUp
			down += fl.bytesDown
		}
		log.Printf("BOND group %s: %d UDP flows, up %.1f MB, down %.1f MB", g.name, len(g.flows), float64(up)/1e6, float64(down)/1e6)
		g.lastFlowReport = now
	}
}
