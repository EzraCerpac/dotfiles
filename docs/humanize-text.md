# humanize-text

`humanize-text` is the local command for sending prose through the configured
CLIProxyAPI and a two-hop translation chain. Google Translate always handles
the first hop. Niutrans handles the final hop when its Keychain entry exists;
otherwise Google Translate handles that hop too. The active providers receive
the text during a run. The command is installed on normal macOS profiles only
and does not add files to the thesis checkout by itself.

Run `humanize-text configure` once to choose a proxy model, save the model in
`~/.config/humanize-text/config.toml`, and optionally store a Niutrans key in
macOS Keychain. The last stage runs a short disposable smoke test. The wizard
asks for the key with hidden input when Niutrans is selected. It never writes
the key to a config file. If
CLIProxyAPI is stopped, the wizard starts its existing Homebrew service and
waits up to five seconds for the model endpoint.

## Presets

Plain text uses temperature `1.3` and sends the input as one request. A Typst
file selects the Typst preset, uses temperature `1.0`, and processes prose
paragraph by paragraph. The Typst path protects syntax and checks the rebuilt
file before it publishes output. Citations, labels, math, code, URLs, DOIs,
imports, and numeric literals must survive exactly.

The guard protects syntax, not scientific meaning. Translation can change technical
terms, qualifiers, and the roles of reported numbers. For technical writing, compare
the output with the source before accepting it. The guard rejects deleted prose
spans and words moved across protected boundaries; it does not guess repairs.

Typst file mode also runs `typst compile` in the discovered project context.
Clipboard fragments have no project entry point, so `humanize-clipboard
--typst` uses the placeholder, parse, and structural checks without a compile.

## Common commands

```sh
humanize-text notes.txt
humanize-text --text "A short piece of prose."
humanize-text chapter.typ
humanize-text --write chapter.typ
humanize-text --output revised.typ chapter.typ
humanize-text --whole chapter.typ
humanize-text --language de --cache-dir ~/.cache/humanize-text chapter.typ
humanize-text --instructions-file thesis-rewrite.txt --cache-dir ~/.cache/humanize-text chapter.typ
humanize-clipboard
humanize-clipboard --typst
```

Plain file and stdin results go to standard output unless `--write` or
`--output` selects another destination.

English is the default output language. Use `--language de` for German. For a
long paragraph-by-paragraph run, `--cache-dir PATH` saves each validated chunk
after it succeeds. Repeating the command with the same source chunks, language,
model, temperature, pipeline settings, and pinned upstream version reuses those
outputs. Cache files contain source-derived hashes and rewritten text, never API
keys, but the rewritten text itself may be sensitive.

Use `--instructions-file PATH` to append project-specific rewrite rules to the
system prompt for both LLM steps. The four-step translation chain stays the
same. The file path is not part of the cache key; its UTF-8 content is, so
changing the rules cannot reuse output produced under older rules.

The default Typst file flow creates a JJ commit with a message like
`docs(manuscript): revise chapter prose`. Use `--write` to update only the
named working-copy file. Use `--output` to create a separate file. Existing
output files are not overwritten.

The defaults live in `~/.config/humanize-text/defaults.toml`. Personal choices
belong in `~/.config/humanize-text/config.toml`; keep secrets in Keychain.

## Troubleshooting

If setup says the proxy is unavailable, start CLIProxyAPI on
`127.0.0.1:8317` and rerun the wizard. If a smoke test fails, check the saved
model and the configured translation providers. A failed Typst guard or cloud request
leaves the source file and clipboard unchanged.
