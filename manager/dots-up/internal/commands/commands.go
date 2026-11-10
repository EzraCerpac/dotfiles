// Package commands describes the public dots commands without implementing their policies.
package commands

type Spec struct {
	Name, Label, Group, Description, Mode string
	Sensitive, NeedsArgs                  bool
}

var specs = []Spec{
	{"status", "Machine status", "Inspect", "Browse files, tools, source and backup health", "inspect", false, false},
	{"reports", "Saved reports", "Inspect", "Browse completed command reports", "concise", false, false},
	{"up", "Update machine", "Maintain", "Sync configuration and update tools and plugins", "dashboard", false, false},
	{"sync", "Sync configuration", "Maintain", "Fetch main and apply configuration", "dashboard", false, false},
	{"apply", "Apply dotfiles", "Maintain", "Apply declared dotfiles and templates", "dashboard", false, false},
	{"add", "Add software", "Software", "Install and record tools or native packages", "dashboard", false, true},
	{"remove", "Remove software", "Software", "Uninstall software and remove declarations", "dashboard", false, true},
	{"backup", "Back up settings", "Settings", "Save and publish encrypted settings", "dashboard", false, false},
	{"restore", "Restore settings", "Settings", "Restore private settings history", "dashboard", true, false},
	{"atuin-login", "Atuin login", "Settings", "Finish Atuin login and authentication", "dashboard", true, false},
	{"atuin-bundle", "Atuin bundle", "Settings", "Prepare the private Atuin bundle", "dashboard", true, false},
	{"bootstrap", "Bootstrap machine", "Setup", "Install and apply declared machine setup", "dashboard", true, false},
	{"remote", "Bootstrap remote host", "Setup", "Bootstrap a machine over existing SSH", "dashboard", true, true},
	{"bundle", "Private bundle", "Setup", "Create or check encrypted bootstrap inputs", "dashboard", true, true},
	{"test", "Run tests", "Development", "Run repository test suites", "dashboard", false, false},
	{"publish", "Publish source", "Development", "Review changes and open or update a PR", "dashboard", false, true},
	{"plan", "Native setup plan", "Advanced", "Print the existing native mise plan", "concise", false, false},
	{"houseatlas", "HouseAtlas maintenance", "Advanced", "Unavailable binding; sends no request", "concise", false, true},
}

func Canonical(name string) string {
	switch name {
	case "update":
		return "up"
	case "uninstall":
		return "remove"
	}
	return name
}
func Lookup(name string) (Spec, bool) {
	name = Canonical(name)
	for _, s := range specs {
		if s.Name == name {
			return s, true
		}
	}
	return Spec{}, false
}
func All() []Spec { return append([]Spec(nil), specs...) }
