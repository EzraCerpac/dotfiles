# Shared planning source

`plan.json` is UTF-8 JSON, schema version 1. Keep only useful narrative sections. Each section is `{ "title": "Current state", "body": "Evidence-backed Markdown prose…" }`; sections appear before the generated work breakdown. Typical sections are outcome/first version, current state/evidence, target architecture and ownership, decisions, parallel work/integration, risks, acceptance, and rollout/recovery. They are suggestions, not mandatory boilerplate. Do not duplicate task records inside prose.

Required top-level fields: `schema_version: 1`, nonempty `title`, `status` (for example `Planning; implementation not started`), `sections` (list), `tasks` (nonempty list), `target_ids` (nonempty list of task IDs defining the requested release or outcome). Optional `duration_unit` (default `effort units`) and `milestones` (list).

Each task:

```json
{
  "id": "P-10",
  "title": "Freeze the public read contract",
  "phase": "Design",
  "workstream": "API",
  "owner": "Contract owner",
  "deliverables": ["Versioned schema and synthetic fixtures"],
  "depends_on": [],
  "prerequisites": ["Audience decision confirmed"],
  "acceptance": ["Both consumers validate against the same fixtures"],
  "optional": false,
  "kind": "task",
  "duration": null
}
```

`id` uses letters/digits/hyphens/underscores, starts with a letter, and stays short. All shown fields except `optional`, `kind`, and `duration` are required. `kind` is `task` or `gate`; `optional` defaults false. `depends_on` contains task IDs only; `prerequisites` contains external conditions/decisions and may be empty. Deliverables and acceptance must be nonempty. Gates state who can satisfy them and what evidence exits them. `duration` is an optional finite nonnegative estimate in one consistent unit; `null` means unknown. Zero is appropriate for a gate only if waiting is excluded and explicitly disclosed. Never invent durations to get a critical-path number.

Milestones have `id`, `title`, `depends_on` (nonempty list of task IDs), `acceptance` (nonempty list), and `owner`. For an action requiring approval, a milestone label alone is insufficient: put the actual gate in `tasks` so downstream prerequisites include it. Optional tasks may depend on required tasks; a required release target cannot depend on optional work. For a requested optional extension, make that extension required in its own plan/target.

Edges run **predecessor → dependent**. Topological layers are earliest dependency readiness, not assignments or a guarantee that resources can work simultaneously. The analysis considers the target IDs and all their ancestors. With complete estimates it computes earliest finish, latest start, zero-slack tasks/edges (including tied critical paths), and one representative longest path. Without complete estimates it chooses one longest structural chain by node count and labels it accordingly. Disconnected optional branches do not extend the release's critical path. External prerequisites and shared-resource waits remain visible and must be assessed outside the numerical model.

Generate all artifacts with `scripts/plan.py`. Rendering treats task strings as text, escapes embedded JSON for HTML, and uses generated safe Mermaid node keys. Section bodies are trusted author-written Markdown; do not paste executable or unreviewed source instructions into them. Generated views are local snapshots, not live editors. Regenerate after source changes; never hand-edit the HTML's embedded data or the task table.
