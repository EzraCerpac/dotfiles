package supervisor

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/ui"
)

func TestEventStreamDecoderPreservesBytesAndFragmentedEvents(t *testing.T) {
	const nonce = "0123456789abcdef0123456789abcdef"
	decoder, err := newEventStreamDecoder(nonce)
	if err != nil {
		t.Fatal(err)
	}
	start := ui.Event{V: 1, Kind: "stage_start", ID: "alpha"}
	end := ui.Event{V: 1, Kind: "stage_end", ID: "alpha", Status: "failed"}
	startJSON, _ := json.Marshal(start)
	endJSON, _ := json.Marshal(end)
	stream := append([]byte("before\n"), framedEvent(nonce, startJSON)...)
	stream = append(stream, []byte("diagnostic\n")...)
	stream = append(stream, framedEvent(nonce, endJSON)...)
	stream = append(stream, []byte("after\n")...)

	var records []outputRecord
	for _, size := range []int{1, 7, 3, 19, 2, 64, len(stream)} {
		if len(stream) == 0 {
			break
		}
		n := min(size, len(stream))
		records = append(records, decoder.feed(stream[:n])...)
		stream = stream[n:]
	}
	records = append(records, decoder.flush()...)

	want := []string{"before\n", "stage_start:alpha", "diagnostic\n", "stage_end:alpha", "after\n"}
	got := make([]string, 0, len(records))
	var pending bytes.Buffer
	for _, record := range records {
		if record.err != nil {
			t.Fatalf("decoder returned an error: %v", record.err)
		}
		if record.event != nil {
			if pending.Len() > 0 {
				got = append(got, pending.String())
				pending.Reset()
			}
			got = append(got, record.event.Kind+":"+record.event.ID)
		} else {
			_, _ = pending.Write(record.bytes)
		}
	}
	if pending.Len() > 0 {
		got = append(got, pending.String())
	}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("decoded order = %#v, want %#v", got, want)
	}
	if bytes.Contains(bytes.Join(byteRecords(records), nil), []byte("dots-up/1:")) {
		t.Fatal("event markers escaped into ordinary output")
	}
}

func TestFramedStageOutputStaysWithItsStage(t *testing.T) {
	oldInteractive, oldStart := hasInteractiveTerminal, startUpdaterBackend
	t.Cleanup(func() {
		hasInteractiveTerminal, startUpdaterBackend = oldInteractive, oldStart
	})
	hasInteractiveTerminal = func() bool { return false }

	const nonce = "abcdef0123456789abcdef0123456789"
	startUpdaterBackend = func(Options, *runFiles, bool) (*backend, *os.File, io.Reader, error) {
		eventR, eventW, err := os.Pipe()
		if err != nil {
			return nil, nil, nil, err
		}
		_ = eventW.Close()
		outputR, outputW, err := os.Pipe()
		if err != nil {
			_ = eventR.Close()
			return nil, nil, nil, err
		}
		command := exec.Command("sh", "-c", "sleep 0.05")
		if err := command.Start(); err != nil {
			_ = eventR.Close()
			_ = outputR.Close()
			_ = outputW.Close()
			return nil, nil, nil, err
		}
		go func() {
			defer outputW.Close()
			writeEvent := func(event ui.Event) {
				payload, _ := json.Marshal(event)
				_, _ = outputW.Write(framedEvent(nonce, payload))
			}
			writeEvent(ui.Event{V: 1, Kind: "run_start", Profile: "nas", Host: "fixture"})
			writeEvent(ui.Event{V: 1, Kind: "stage_start", ID: "alpha", Group: "Tools", Label: "Alpha"})
			_, _ = io.WriteString(outputW, "last failure diagnostic\n")
			writeEvent(ui.Event{V: 1, Kind: "stage_end", ID: "alpha", Status: "failed", ExitCode: 43, Summary: "failed"})
			writeEvent(ui.Event{V: 1, Kind: "stage_start", ID: "beta", Group: "Tools", Label: "Beta"})
			_, _ = io.WriteString(outputW, "beta output\n")
			writeEvent(ui.Event{V: 1, Kind: "stage_end", ID: "beta", Status: "ok", Summary: "completed"})
		}()
		return &backend{command: command, streamNonce: nonce}, eventR, outputR, nil
	}
	state := filepath.Join(t.TempDir(), "state")
	if code := Run(Options{Root: t.TempDir(), StateDir: state}); code != 0 {
		t.Fatalf("run returned %d", code)
	}
	alphaMatches, err := filepath.Glob(filepath.Join(state, "*", "stages", "alpha.log"))
	if err != nil || len(alphaMatches) != 1 {
		t.Fatalf("alpha stage log paths = %v, err = %v", alphaMatches, err)
	}
	betaMatches, err := filepath.Glob(filepath.Join(state, "*", "stages", "beta.log"))
	if err != nil || len(betaMatches) != 1 {
		t.Fatalf("beta stage log paths = %v, err = %v", betaMatches, err)
	}
	alpha := alphaMatches[0]
	beta := betaMatches[0]
	alphaLog, err := os.ReadFile(alpha)
	if err != nil {
		t.Fatal(err)
	}
	betaLog, err := os.ReadFile(beta)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(alphaLog, []byte("last failure diagnostic")) {
		t.Fatalf("alpha log lost its trailing diagnostic: %q", alphaLog)
	}
	if bytes.Contains(betaLog, []byte("last failure diagnostic")) || !bytes.Contains(betaLog, []byte("beta output")) {
		t.Fatalf("stage output was routed incorrectly: beta log %q", betaLog)
	}
}

func framedEvent(nonce string, payload []byte) []byte {
	frame := append([]byte("\x1edots-up/1:"+nonce+":"), payload...)
	return append(frame, 0x1f)
}

func byteRecords(records []outputRecord) [][]byte {
	var result [][]byte
	for _, record := range records {
		if record.event == nil && record.bytes != nil {
			result = append(result, record.bytes)
		}
	}
	return result
}

func TestEventStreamDecoderRejectsInvalidNonce(t *testing.T) {
	if _, err := newEventStreamDecoder("not-a-valid-nonce"); err == nil {
		t.Fatal("invalid nonce accepted")
	}
}

func TestOutputReaderConvertsFramesAcrossWrites(t *testing.T) {
	const nonce = "00112233445566778899aabbccddeeff"
	reader, writer := io.Pipe()
	output := make(chan outputRecord, 8)
	go readOutput(reader, nonce, output)
	payload, _ := json.Marshal(ui.Event{V: 1, Kind: "notice", Summary: "notice"})
	frame := framedEvent(nonce, payload)
	go func() {
		_, _ = writer.Write(frame[:len(frame)/2])
		_, _ = writer.Write(frame[len(frame)/2:])
		_ = writer.Close()
	}()
	var records []outputRecord
	for record := range output {
		records = append(records, record)
	}
	if len(records) != 1 || records[0].event == nil || records[0].event.Summary != "notice" {
		t.Fatalf("decoded records = %#v", records)
	}
}
