// ck-phone: the phone's half of a phone line over USB (v17, request 36, Marko 19.10.2026: "two USB connection ... my
// noting phone ... connected with USB tethering. So please detect and combine these two USB connections into one").
// Android tethers over USB with RNDIS, which macOS cannot speak, and the Nothing A142's USB system refuses NCM ("Could
// not set unsupported function for the GadgetHal"). So the line goes over adb instead: this SOCKS5 server runs on the
// phone from adb's shell (no root, no app), goes out through the phone's own internet (its mobile data), and
// `adb forward` brings it to the Mac, where ck-aggregate dials through it like through any other line.
//
//   ck-phone [-l 127.0.0.1:8858]
//
// TCP CONNECT only (adb forwards TCP). Names are looked up by public resolvers: Android has no /etc/resolv.conf.
package main

import (
	"context"
	"encoding/binary"
	"flag"
	"io"
	"log"
	"net"
	"os"
	"strconv"
	"time"
)

var resolvers = []string{"1.1.1.1:53", "8.8.8.8:53", "1.0.0.1:53"}

func init() {
	n := 0
	net.DefaultResolver = &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
		n++
		var d net.Dialer
		return d.DialContext(ctx, network, resolvers[n%len(resolvers)])
	}}
}

func main() {
	addr := flag.String("l", "127.0.0.1:8858", "listen address")
	flag.Parse()
	ln, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("ck-phone on %s (pid %d)", *addr, os.Getpid())
	for {
		c, err := ln.Accept()
		if err != nil {
			continue
		}
		go handle(c)
	}
}

func handle(c net.Conn) {
	defer c.Close()
	c.SetDeadline(time.Now().Add(20 * time.Second))
	b := make([]byte, 262)
	if _, err := io.ReadFull(c, b[:2]); err != nil || b[0] != 5 {
		return
	}
	if _, err := io.ReadFull(c, b[:b[1]]); err != nil {
		return
	}
	c.Write([]byte{5, 0})
	if _, err := io.ReadFull(c, b[:4]); err != nil || b[1] != 1 {
		c.Write([]byte{5, 7, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	var host string
	switch b[3] {
	case 1:
		io.ReadFull(c, b[:4])
		host = net.IP(b[:4]).String()
	case 3:
		io.ReadFull(c, b[:1])
		n := int(b[0])
		io.ReadFull(c, b[:n])
		host = string(b[:n])
	case 4:
		io.ReadFull(c, b[:16])
		host = net.IP(b[:16]).String()
	default:
		return
	}
	if _, err := io.ReadFull(c, b[:2]); err != nil {
		return
	}
	port := binary.BigEndian.Uint16(b[:2])
	out, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(int(port))), 10*time.Second)
	if err != nil {
		c.Write([]byte{5, 4, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	defer out.Close()
	c.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0})
	c.SetDeadline(time.Time{})
	done := make(chan struct{}, 2)
	pipe := func(dst, src net.Conn) {
		io.Copy(dst, src)
		if t, ok := dst.(*net.TCPConn); ok {
			t.CloseWrite()
		}
		done <- struct{}{}
	}
	go pipe(out, c)
	go pipe(c, out)
	<-done
	// one side is done; the other gets 30 s to finish too
	select {
	case <-done:
	case <-time.After(30 * time.Second):
	}
}
