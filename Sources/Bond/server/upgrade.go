// Zero-downtime upgrades (v71, request 85: "upgrading/restarting the relay must be zero-downtime").
//
//	systemctl reload ckbond  →  SIGHUP  →  the binary on disk (os.Args[0], the new one after install.sh) is started as a
//	child with the SAME listening socket (fd 3), so not one connection is refused; the child says READY on fd 4 and
//	tells systemd it is the main process now (NOTIFY_SOCKET, MAINPID=); the old process stops accepting, sends GOAWAY on
//	every leg (the Mac opens new legs to the child and starts new streams there) and keeps serving its streams until
//	they end (at most -drain), then exits.
//
// SIGTERM / SIGINT (systemctl stop): GOAWAY on every leg, one second for it to leave, exit.
package main

import (
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"
)

func listener(addr string) (net.Listener, bool, error) {
	if os.Getenv("CKBOND_LISTEN_FD") == "3" {
		f := os.NewFile(3, "listener")
		ln, err := net.FileListener(f)
		f.Close()
		os.Unsetenv("CKBOND_LISTEN_FD")
		return ln, true, err
	}
	ln, err := net.Listen("tcp", addr)
	return ln, false, err
}

// readyForParent: a child started by a hand-over tells its parent (fd 4) that it accepts now.
func readyForParent() {
	if os.Getenv("CKBOND_READY_FD") != "4" {
		return
	}
	f := os.NewFile(4, "ready")
	f.Write([]byte{1})
	f.Close()
	os.Unsetenv("CKBOND_READY_FD")
}

// sdNotify: systemd's notify protocol, standard library only (a datagram to $NOTIFY_SOCKET). Nothing without systemd.
func sdNotify(msg string) {
	name := os.Getenv("NOTIFY_SOCKET")
	if name == "" {
		return
	}
	c, err := net.DialUnix("unixgram", nil, &net.UnixAddr{Name: name, Net: "unixgram"})
	if err != nil {
		log.Printf("BOND notify: %v", err)
		return
	}
	defer c.Close()
	c.Write([]byte(msg))
}

func (s *server) isDraining() bool { s.mu.Lock(); defer s.mu.Unlock(); return s.draining }

func (s *server) signals(ln net.Listener, drainFor time.Duration) {
	ch := make(chan os.Signal, 4)
	signal.Notify(ch, syscall.SIGHUP, syscall.SIGTERM, syscall.SIGINT)
	for sig := range ch {
		if sig == syscall.SIGHUP {
			if s.isDraining() {
				continue
			}
			if !s.handOver(ln) {
				continue // the child did not come up: this process keeps serving
			}
			s.drain(drainFor)
			return
		}
		log.Printf("BOND %v: GOAWAY to every leg, exit in 1 s", sig)
		s.mu.Lock()
		s.draining = true
		s.mu.Unlock()
		ln.Close()
		s.goaway()
		time.Sleep(time.Second)
		os.Exit(0)
	}
}

// handOver starts the binary on disk with this listening socket and waits (10 s) for it to accept.
func (s *server) handOver(ln net.Listener) bool {
	tl, ok := ln.(*net.TCPListener)
	if !ok {
		return false
	}
	lf, err := tl.File()
	if err != nil {
		log.Printf("BOND hand-over: no socket copy: %v", err)
		return false
	}
	defer lf.Close()
	rr, rw, err := os.Pipe()
	if err != nil {
		return false
	}
	defer rr.Close()
	cmd := exec.Command(os.Args[0], os.Args[1:]...)
	cmd.Env = append(os.Environ(), "CKBOND_LISTEN_FD=3", "CKBOND_READY_FD=4")
	cmd.ExtraFiles = []*os.File{lf, rw}
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Start(); err != nil {
		rw.Close()
		log.Printf("BOND hand-over: %s did not start: %v; this process keeps serving", os.Args[0], err)
		return false
	}
	rw.Close()
	got := make(chan bool, 1)
	go func() { b := make([]byte, 1); n, _ := rr.Read(b); got <- n == 1 }()
	select {
	case ok := <-got:
		if !ok {
			log.Printf("BOND hand-over: the new process %d ended before it was ready; this process keeps serving", cmd.Process.Pid)
			return false
		}
	case <-time.After(10 * time.Second):
		cmd.Process.Kill()
		log.Printf("BOND hand-over: the new process was not ready in 10 s; killed, this process keeps serving")
		return false
	}
	go cmd.Wait() // reap it if it ever ends while this one still runs
	s.mu.Lock()
	s.draining = true
	s.mu.Unlock()
	ln.Close() // the child holds the same socket: nothing in the queue is lost
	log.Printf("BOND hand-over: pid %d accepts now; this process (pid %d) sends GOAWAY and serves its streams until they end", cmd.Process.Pid, os.Getpid())
	return true
}

func (s *server) goaway() {
	s.mu.Lock()
	gs := make([]*group, 0, len(s.groups))
	for _, g := range s.groups {
		gs = append(gs, g)
	}
	s.mu.Unlock()
	for _, g := range gs {
		g.mu.Lock()
		for _, l := range g.legs {
			g.ctl(l, frame{typ: fGoaway})
		}
		g.mu.Unlock()
	}
}

func (s *server) drain(limit time.Duration) {
	s.goaway()
	end := time.Now().Add(limit)
	for time.Now().Before(end) {
		time.Sleep(time.Second)
		s.mu.Lock()
		gs := make([]*group, 0, len(s.groups))
		for _, g := range s.groups {
			gs = append(gs, g)
		}
		s.mu.Unlock()
		open := 0
		for _, g := range gs {
			g.mu.Lock()
			for _, st := range g.streams {
				if !st.done {
					open++
				}
			}
			g.mu.Unlock()
		}
		if open == 0 {
			log.Printf("BOND hand-over: no stream left on the old process, exit")
			os.Exit(0)
		}
	}
	log.Printf("BOND hand-over: drain time over, exit")
	os.Exit(0)
}
