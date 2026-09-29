# Atuin across machines

Atuin uses the same `EzraCerpac` account and history key on the Mac, CerpacNAS,
and DriehuisNAS. Ctrl-R searches shared history; Up/Down still recall only this
terminal session. At an empty prompt, `?` opens Atuin AI. Within a command,
`?` remains a normal character.

Bootstrap uses the separate `encrypted/atuin.json.age` bundle for enrollment.
Each machine decrypts it with its own age identity; passwords and history keys
are never passed as command arguments. The initial `dots atuin-bundle` wizard
accepts authorized public recipients and asks for the password without echoing it.
It captures the existing history key locally and writes ciphertext only.

A new host must have its own age identity, and an enrolled host must include its
public recipient in a reviewed replacement bundle before it can decrypt it.
Keep private age keys outside the repositories. If bootstrap stops for a
two-factor code, open a terminal and run `dots atuin-login`. It supplies the
bundled password and history key privately, then asks you for the one-time code
without echoing it. With an external age identity, use
`dots atuin-login --identity /path/to/key`.

For browser authorization, run `dots atuin-login --browser`. Open the displayed
Atuin Hub link, sign in as `EzraCerpac`, and leave the terminal open until login
and synchronization finish. The history key still comes from your encrypted
bundle; you do not need to reveal or paste it. Then rerun `dots bootstrap` to
finish any deferred setup stages. Already-correct logins and history are preserved.

`dots status` reports Atuin installation, history login, last synchronization,
and AI readiness separately. An enabled AI binding does not prove Hub login:
complete the native Atuin Hub linking/browser flow if it asks for one.

The WakaTime/mail bundle also permits the two authorized NAS keys to decrypt it.
That permission does not overwrite any existing application configuration.
