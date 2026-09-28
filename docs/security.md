# Security guardrails

This repository is public. Three guardrails keep private material out of it
and make published commits verifiable.

## Secret-shaped files stay ignored

`.gitignore` re-includes `dotfiles/`, `templates/` and `seeds/` so that
user-global ignore patterns cannot hide managed files. The block at the end of
`.gitignore` repeats the secret patterns after those re-includes: `.env*`,
`secrets/` directories, `*.local`, keys and certificates (`*.pem`, `*.key`,
`*.p12`), private SSH keys and age identities. `tests/test_gitignore.py` checks
both directions: such files stay ignored, and no managed file is ignored.
Commit private inputs only as age ciphertext under `encrypted/`.

## `dots publish` scans before it pushes

Before asking for confirmation, `dots publish` runs gitleaks over every commit
it is about to publish (`main@origin..` the published revision). A token
added in one commit and removed in the next is still refused: once pushed,
both commits are public. Findings are printed with the secret redacted, and
nothing is pushed. gitleaks is part of the base profile; if it is missing,
publishing stops and `dots up` installs it.

CI scans the complete history on every pull request with the same
`.gitleaks.toml`. For a false positive, prefer a narrow path allowlist in
`.gitleaks.toml` (as for Julia `Manifest.toml` package UUIDs) over a blanket
rule, or mark the line with a trailing `gitleaks:allow` comment.

## Commits are signed with your SSH key

On the workstation profile, Git signs every commit and annotated tag with
`~/.ssh/id_ed25519`, and JJ signs commits when it pushes them
(`~/.config/jj/conf.d/signing.toml`). JJ signs on push rather than on every
rewrite, so the key is used once per push. The NAS profile does not sign.

One-time setup, so GitHub shows those commits as verified:

```sh
gh ssh-key add ~/.ssh/id_ed25519.pub --type signing --title "$(hostname -s) signing"
```

An authentication key is not automatically a signing key on GitHub; the key
must be added again with `--type signing`. The key must be loadable without a
prompt, as it is when macOS Keychain holds its passphrase (`UseKeychain` in
the SSH config). The former GPG key `D041C1286F71DBDF` is no longer used.
