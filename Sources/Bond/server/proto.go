// ckbond v1: the wire (docs/ckbond.md). Frames inside AES-256-GCM records, one frame per record:
//
//	record: len u16 (ciphertext + tag) | ciphertext | tag(16)   nonce = 4 zero bytes | u64 counter (per leg and direction)
//	frame:  type u8 | stream u32 | seq u32 | len u16 | payload (<= 16 KB)
package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"errors"
)

const (
	fOpen     byte = 1 // Mac -> server, payload host:port, seq 0
	fOpenOK   byte = 2 // server -> Mac, seq 0
	fOpenFail byte = 3 // server -> Mac, seq 0, payload a short reason
	fData     byte = 4
	fFin      byte = 5
	fRst      byte = 6 // not sequenced
	fAck      byte = 7 // stream != 0: seq = next sequenced frame expected (cumulative, delivered); stream 0: leg ack, payload u64
	fPing     byte = 8 // payload: the sender's clock, echoed in PONG
	fPong     byte = 9
	fWelcome  byte = 10 // the server's first record on a leg: the handshake worked

	hdrLen     = 11
	maxPayload = 16384
	tagLen     = 16
	maxRecord  = hdrLen + maxPayload + tagLen
)

var errFrame = errors.New("bad frame")

// sequenced frames are reliable: numbered per stream and direction, resent when their leg dies, delivered in order.
func sequenced(t byte) bool { return t >= fOpen && t <= fFin }

type frame struct {
	typ         byte
	stream, seq uint32
	payload     []byte
}

func (f frame) size() int { return hdrLen + len(f.payload) }

func (f frame) encode() []byte {
	b := make([]byte, hdrLen+len(f.payload))
	b[0] = f.typ
	binary.BigEndian.PutUint32(b[1:], f.stream)
	binary.BigEndian.PutUint32(b[5:], f.seq)
	binary.BigEndian.PutUint16(b[9:], uint16(len(f.payload)))
	copy(b[hdrLen:], f.payload)
	return b
}

func decodeFrame(b []byte) (frame, error) {
	if len(b) < hdrLen {
		return frame{}, errFrame
	}
	n := int(binary.BigEndian.Uint16(b[9:]))
	if n > maxPayload || hdrLen+n != len(b) {
		return frame{}, errFrame
	}
	return frame{typ: b[0], stream: binary.BigEndian.Uint32(b[1:]), seq: binary.BigEndian.Uint32(b[5:]),
		payload: append([]byte(nil), b[hdrLen:]...)}, nil
}

// One direction of one leg: its key and its record counter.
type aeadDir struct {
	a     cipher.AEAD
	ctr   uint64
	nonce [12]byte
}

func newDir(key []byte) *aeadDir {
	b, err := aes.NewCipher(key)
	if err != nil {
		panic(err)
	}
	a, err := cipher.NewGCM(b)
	if err != nil {
		panic(err)
	}
	return &aeadDir{a: a}
}

func (d *aeadDir) next() []byte {
	binary.BigEndian.PutUint64(d.nonce[4:], d.ctr)
	d.ctr++
	return d.nonce[:]
}

// sealRecord appends len | ciphertext | tag of one frame to dst.
func (d *aeadDir) sealRecord(dst, plain []byte) []byte {
	start := len(dst)
	dst = append(dst, 0, 0)
	dst = d.a.Seal(dst, d.next(), plain, nil)
	binary.BigEndian.PutUint16(dst[start:], uint16(len(dst)-start-2))
	return dst
}

func (d *aeadDir) open(rec []byte) ([]byte, error) { return d.a.Open(rec[:0], d.next(), rec, nil) }

// HKDF-SHA256 (RFC 5869) for one 32-byte key: Go 1.22 has no crypto/hkdf in its standard library.
func hkdf32(ikm, salt, info []byte) []byte {
	m := hmac.New(sha256.New, salt)
	m.Write(ikm)
	prk := m.Sum(nil)
	m = hmac.New(sha256.New, prk)
	m.Write(info)
	m.Write([]byte{1})
	return m.Sum(nil)
}

// The client's proof: HMAC-SHA256(token, "ckbond1" | snonce | cnonce | clientID).
func authMAC(token, snonce, cnonce, cid []byte) []byte {
	m := hmac.New(sha256.New, token)
	m.Write([]byte("ckbond1"))
	m.Write(snonce)
	m.Write(cnonce)
	m.Write(cid)
	return m.Sum(nil)
}

// The two keys of a leg: Mac -> server and server -> Mac.
func sessionKeys(token, snonce, cnonce []byte) (c2s, s2c []byte) {
	salt := append(append([]byte{}, snonce...), cnonce...)
	return hkdf32(token, salt, []byte("ckbond1 c2s")), hkdf32(token, salt, []byte("ckbond1 s2c"))
}
