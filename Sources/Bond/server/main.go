// ck-bond-server: the far end of ckbond v1 (request 84, Marko 14.11.2026: bonding through the Oracle Cloud server).
// The Mac opens one TCP "leg" through each of its lines (cable, Wi-Fi, phones) to this server; the legs of one Mac form a
// group. Every connection of the Mac is a stream cut into frames that travel over all legs; here they are put back in
// order and the server talks to the destination as one normal TCP connection. Replies go back over all legs.
//
//	ck-bond-server [-listen :443] [-token-file /etc/ckbond/token] [-allow-local]
//
// The token (hex) is never logged. Standard library only.
package main

import (
	"crypto/hmac"
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

const relayVersion = "v71"

const (
	maxGroups      = 64
	maxLegsTotal   = 512
	handshakeLimit = 10 * time.Second
	failWindow     = 10 * time.Minute
	failsToBan     = 10
	banFor         = 10 * time.Minute
)

type failRec struct {
	n            int
	first, until time.Time
}

type server struct {
	token      []byte
	allowLocal bool
	mu         sync.Mutex
	groups     map[[16]byte]*group
	fails      map[string]*failRec
	legs       int
	draining   bool
}

func main() {
	listen := flag.String("listen", ":443", "address to listen on")
	tokenFile := flag.String("token-file", "/etc/ckbond/token", "file holding the shared token (hex, 64 characters)")
	allowLocal := flag.Bool("allow-local", false, "let streams reach loopback and private addresses (the loopback test only)")
	drainFor := flag.Duration("drain", 10*time.Minute, "after a hand-over, how long the old process serves its streams at most")
	flag.Parse()
	log.SetFlags(log.LstdFlags)
	raw, err := os.ReadFile(*tokenFile)
	if err != nil {
		log.Fatalf("BOND cannot read the token file %s", *tokenFile)
	}
	token, err := hex.DecodeString(strings.TrimSpace(string(raw)))
	if err != nil || len(token) < 16 {
		log.Fatalf("BOND the token file %s must hold at least 32 hex characters", *tokenFile)
	}
	s := &server{token: token, allowLocal: *allowLocal, groups: map[[16]byte]*group{}, fails: map[string]*failRec{}}
	ln, inherited, err := listener(*listen)
	if err != nil {
		log.Fatalf("BOND cannot listen on %s: %v", *listen, err)
	}
	how := "new socket"
	if inherited {
		how = "the socket handed over by the old process"
	}
	log.Printf("BOND ckbond v1 (%s) pid %d on %s, %s (local destinations %s)", relayVersion, os.Getpid(), *listen, how, map[bool]string{true: "allowed", false: "refused"}[*allowLocal])
	readyForParent()
	sdNotify(fmt.Sprintf("MAINPID=%d\nREADY=1", os.Getpid()))
	go s.signals(ln, *drainFor)
	for {
		c, err := ln.Accept()
		if err != nil {
			if s.isDraining() {
				select {} // the successor accepts now; signals() ends this process when its streams are done
			}
			time.Sleep(50 * time.Millisecond)
			continue
		}
		go s.handle(c)
	}
}

func (s *server) banned(ip string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	r := s.fails[ip]
	return r != nil && time.Now().Before(r.until)
}

// A failed handshake (wrong proof, or nothing within 10 s): ten in ten minutes and the address is refused for ten.
func (s *server) failed(ip string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	r := s.fails[ip]
	if r == nil || now.Sub(r.first) > failWindow {
		r = &failRec{first: now}
		s.fails[ip] = r
	}
	r.n++
	if r.n == failsToBan {
		r.until = now.Add(banFor)
		log.Printf("BOND %s refused for 10 min after %d failed handshakes", ip, r.n)
	}
	if len(s.fails) > 10000 {
		for k, v := range s.fails {
			if now.Sub(v.first) > failWindow && now.After(v.until) {
				delete(s.fails, k)
			}
		}
	}
}

func (s *server) handle(c net.Conn) {
	ip, _, _ := net.SplitHostPort(c.RemoteAddr().String())
	if s.banned(ip) {
		c.Close()
		return
	}
	if tc, ok := c.(*net.TCPConn); ok {
		tc.SetNoDelay(true)
	}
	c.SetDeadline(time.Now().Add(handshakeLimit))
	snonce := make([]byte, 32)
	if _, err := rand.Read(snonce); err != nil {
		c.Close()
		return
	}
	if _, err := c.Write(snonce); err != nil {
		c.Close()
		return
	}
	hello := make([]byte, 80) // cnonce(32) | clientID(16) | HMAC(32)
	if _, err := io.ReadFull(c, hello); err != nil {
		s.failed(ip)
		c.Close()
		return
	}
	cnonce, cid, mac := hello[:32], hello[32:48], hello[48:80]
	if !hmac.Equal(mac, authMAC(s.token, snonce, cnonce, cid)) {
		s.failed(ip) // closed at once, no reply
		c.Close()
		return
	}
	c.SetDeadline(time.Time{})
	c2s, s2c := sessionKeys(s.token, snonce, cnonce)
	var id [16]byte
	copy(id[:], cid)
	s.mu.Lock()
	full := s.legs >= maxLegsTotal
	if !full {
		s.legs++
	}
	s.mu.Unlock()
	if full {
		c.Close()
		return
	}
	defer func() { s.mu.Lock(); s.legs--; s.mu.Unlock() }()
	g := s.group(id)
	if g == nil {
		c.Close()
		return
	}
	l := &leg{conn: c, g: g, tx: newDir(s2c), rx: newDir(c2s), remote: ip}
	if !g.addLeg(l) {
		c.Close()
		return
	}
	go l.writer()
	l.reader()
}

func (s *server) group(id [16]byte) *group {
	s.mu.Lock()
	defer s.mu.Unlock()
	if g := s.groups[id]; g != nil {
		return g
	}
	if len(s.groups) >= maxGroups {
		log.Printf("BOND %d groups already: a new one refused", maxGroups)
		return nil
	}
	g := newGroup(s, id)
	s.groups[id] = g
	go g.loop()
	return g
}

func (s *server) drop(g *group) {
	s.mu.Lock()
	if s.groups[g.id] == g {
		delete(s.groups, g.id)
	}
	s.mu.Unlock()
}
