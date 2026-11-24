package main

// v95: TCP_NOTSENT_LOWAT (linux/tcp.h 25): the kernel keeps at most this much unsent on a leg; the rest waits in the
// relay's own queue, where copies and young streams can go first.
const tcpNotsentLowat = 25
