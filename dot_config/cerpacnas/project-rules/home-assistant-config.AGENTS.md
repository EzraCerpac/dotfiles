# Home Assistant production workflow

GitHub `main` is canonical and production-facing. CerpacNAS is the execution
host. Mac and NAS agents may initiate changes, but every persistent live
mutation finishes through the single CerpacNAS transaction lease.

## Run each task

1. **Orient.** Run `jj status` and inspect current change, parents, and
   bookmarks. Run `jj git fetch`, compare `main` with `main@origin`, and read
   incoming changes for intent and safety impact. Start mutation only when the
   working commit is clean, empty, and based on synchronized `main`.
2. **Choose lane.** Use the live bridge for bounded, reversible automation
   changes. Use staging for upgrades, third-party dependencies, blueprints,
   climate, pairing, radio changes, or behavior whose failure cannot be safely
   checked live. Read `docs/live-agent-workflow.md` before live bridge or
   deployment work; read `docs/staging-runbook.md` before staging work.
3. **Act.** For an explicit immediate request, perform the Home Assistant
   action first. Clarify ambiguous device, sensor, threshold, duration, or
   target before acting. Put one deterministic agent automation per file in
   `live/automations/`; leave UI-owned `automations.yaml` intact.
4. **Transact.** Let the bridge atomically write, run Home Assistant's complete
   configuration check, reload, verify runtime state, create a short `Live: …`
   commit, move `main`, push, and append the external redacted audit record.
   Validation or reload failure restores prior behavior. Push failure keeps
   verified behavior active and marked unpublished; fetch, merge, revalidate,
   and retry. Unresolved conflicts stop publication without changing live
   behavior.
5. **Close.** Inspect `jj diff`, `jj status`, and local/remote `main`. Successful
   persistence ends with published `main` and a clean empty working commit above
   it. Keep each commit focused and described; never create a child on an
   undescribed commit.

## Repository boundary

Version deliberate human- and agent-authored configuration, bridge code, tests,
and documentation. Keep credentials, tokens, secrets, `.storage`, pairing
state, device/entity registries, databases, backups, logs, generated
dependencies, and live device data outside Git. Operate live Home Assistant
only through structured bridge/API tools; make no direct edits to live runtime
state unless the task explicitly requires them.
