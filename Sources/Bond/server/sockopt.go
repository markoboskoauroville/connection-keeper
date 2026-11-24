package main

import (
	"net"
	"syscall"
)

// setLowat (v95): a leg's unsent bytes in the kernel at most n; nil-safe, best effort (an error leaves the default).
func setLowat(c net.Conn, n int) error {
	tc, ok := c.(*net.TCPConn)
	if !ok {
		return nil
	}
	rc, err := tc.SyscallConn()
	if err != nil {
		return err
	}
	var serr error
	if err := rc.Control(func(fd uintptr) { serr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, tcpNotsentLowat, n) }); err != nil {
		return err
	}
	return serr
}
