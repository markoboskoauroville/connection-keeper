#!/usr/bin/env python3
"""CI only: a UDP echo on 127.0.0.1:<port> for the bond selftest."""
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", int(sys.argv[1])))
while True:
    d, a = s.recvfrom(65535)
    s.sendto(d, a)
