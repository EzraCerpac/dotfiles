package supervisor

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/ui"
)

const (
	streamEventStart    = "\x1edots-up/1:"
	streamEventEnd      = byte(0x1f)
	maxStreamEventBytes = 1 << 20
)

type outputRecord struct {
	bytes []byte
	event *ui.Event
	err   error
}

type eventStreamDecoder struct {
	prefix  []byte
	pending []byte
}

func newStreamNonce() (string, error) {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", fmt.Errorf("generate updater stream nonce: %w", err)
	}
	return hex.EncodeToString(raw[:]), nil
}

func newEventStreamDecoder(nonce string) (*eventStreamDecoder, error) {
	if len(nonce) != 32 || strings.Trim(nonce, "0123456789abcdef") != "" {
		return nil, errors.New("invalid updater stream nonce")
	}
	return &eventStreamDecoder{prefix: []byte(streamEventStart + nonce + ":")}, nil
}

func (d *eventStreamDecoder) feed(chunk []byte) []outputRecord {
	d.pending = append(d.pending, chunk...)
	var records []outputRecord
	for len(d.pending) > 0 {
		start := bytes.Index(d.pending, d.prefix)
		if start < 0 {
			keep := 0
			maxKeep := min(len(d.pending), len(d.prefix)-1)
			for n := maxKeep; n > 0; n-- {
				if bytes.Equal(d.pending[len(d.pending)-n:], d.prefix[:n]) {
					keep = n
					break
				}
			}
			flush := len(d.pending) - keep
			if flush > 0 {
				records = append(records, outputRecord{bytes: append([]byte(nil), d.pending[:flush]...)})
				d.pending = append(d.pending[:0], d.pending[flush:]...)
			}
			break
		}
		if start > 0 {
			records = append(records, outputRecord{bytes: append([]byte(nil), d.pending[:start]...)})
			d.pending = d.pending[start:]
		}
		end := bytes.IndexByte(d.pending[len(d.prefix):], streamEventEnd)
		if end < 0 {
			if len(d.pending) > maxStreamEventBytes+len(d.prefix) {
				records = append(records, outputRecord{err: errors.New("updater event frame exceeds 1 MiB")})
				records = append(records, outputRecord{bytes: append([]byte(nil), d.pending...)})
				d.pending = d.pending[:0]
			}
			break
		}
		if end > maxStreamEventBytes {
			records = append(records, outputRecord{err: errors.New("updater event frame exceeds 1 MiB")})
			frameLen := len(d.prefix) + end + 1
			records = append(records, outputRecord{bytes: append([]byte(nil), d.pending[:frameLen]...)})
			d.pending = d.pending[frameLen:]
			continue
		}
		frameLen := len(d.prefix) + end + 1
		var event ui.Event
		payload := d.pending[len(d.prefix) : len(d.prefix)+end]
		if err := json.Unmarshal(payload, &event); err != nil || event.V != 1 {
			if err == nil {
				err = fmt.Errorf("unsupported updater event version %d", event.V)
			}
			records = append(records, outputRecord{err: fmt.Errorf("invalid updater event frame: %w", err)})
			records = append(records, outputRecord{bytes: append([]byte(nil), d.pending[:frameLen]...)})
		} else {
			records = append(records, outputRecord{event: &event})
		}
		d.pending = d.pending[frameLen:]
	}
	return records
}

func (d *eventStreamDecoder) flush() []outputRecord {
	if len(d.pending) == 0 {
		return nil
	}
	leftover := append([]byte(nil), d.pending...)
	d.pending = d.pending[:0]
	return []outputRecord{{err: errors.New("incomplete updater event frame at end of output stream")}, {bytes: leftover}}
}
