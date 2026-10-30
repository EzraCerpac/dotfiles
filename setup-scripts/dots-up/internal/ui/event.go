package ui

// Event is one record from the supervisor's version 1 JSONL event stream.
// Fields unused by a particular kind are omitted by the sender.
type Event struct {
	V          int    `json:"v"`
	Kind       string `json:"kind"`
	ID         string `json:"id,omitempty"`
	Profile    string `json:"profile,omitempty"`
	Host       string `json:"host,omitempty"`
	Group      string `json:"group,omitempty"`
	Label      string `json:"label,omitempty"`
	Terminal   string `json:"terminal,omitempty"`
	Status     string `json:"status,omitempty"`
	ExitCode   int    `json:"exit_code,omitempty"`
	Summary    string `json:"summary,omitempty"`
	Action     string `json:"action,omitempty"`
	Stage      string `json:"stage,omitempty"`
	Item       string `json:"item,omitempty"`
	Before     string `json:"before,omitempty"`
	After      string `json:"after,omitempty"`
	Severity   string `json:"severity,omitempty"`
	DurationMS int64  `json:"duration_ms,omitempty"`
	LogPath    string `json:"log_path,omitempty"`
}

type controlRecord struct {
	V    int    `json:"v"`
	Kind string `json:"kind"`
	ID   string `json:"id,omitempty"`
}
