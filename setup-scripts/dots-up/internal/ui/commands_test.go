package ui

import (
	"fmt"
	"strings"
	"testing"

	"github.com/charmbracelet/x/ansi"
)

func TestStatusInventoryKeepsSelectedAreaAndFooterVisible(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m.Width, m.Height = 100, 24
	m.apply(Event{V: 1, Kind: "run_start", Command: "status"})
	for i := 0; i < 40; i++ {
		m.apply(Event{V: 1, Kind: "item_upsert", ID: fmt.Sprint(i), Group: fmt.Sprintf("Area%02d", i), Label: fmt.Sprintf("Resource%02d", i), Status: "missing", Summary: "not present"})
	}
	m.apply(Event{V: 1, Kind: "run_end"})
	m.selectGroup(39)
	content := ansi.Strip(m.View().Content)
	if !strings.Contains(content, "Area39") || !strings.Contains(content, "earlier areas") || !strings.Contains(content, "Finished") {
		t.Fatalf("selected area, scroll context or footer hidden:\n%s", content)
	}
	if strings.Count(strings.TrimSpace(content), "\n")+1 > m.Height {
		t.Fatalf("inventory exceeds terminal height:\n%s", content)
	}
	if strings.Contains(content, "pending") {
		t.Fatalf("missing resources presented as pending:\n%s", content)
	}
}

func TestRepeatedOperationReplacesItsRunningRow(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	for i := 0; i < 2; i++ {
		m.apply(Event{V: 1, Kind: "stage_start", ID: "install:tool", Group: "Software", Label: "tool"})
		m.apply(Event{V: 1, Kind: "stage_end", ID: "install:tool", Status: "ok"})
	}
	if len(m.Stages) != 1 || m.Stages[0].Status != "ok" {
		t.Fatalf("repeated operation left stale rows: %+v", m.Stages)
	}
}
