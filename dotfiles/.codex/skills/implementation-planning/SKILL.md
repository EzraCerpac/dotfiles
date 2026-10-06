---
name: implementation-planning
description: Create evidence-grounded implementation plans for substantial projects, migrations, or refactors with several workstreams or shared contracts. Define ownership, deliverables, acceptance gates, and dependencies, with an interactive Visualize view. Use a concise checklist for small bounded changes.
---

# Implementation planning

Build a plan someone can use to decide, assign, implement, and verify work. Scale it to the request: for a small change, give the useful steps and acceptance check without a task database, architecture document, or diagram. Planning does not itself authorize implementation; preserve authorization already given by the user rather than adding a universal approval ceremony.

## Ground the plan

Read applicable instructions and the actual current sources before proposing a replacement. Audit only what affects the goal: existing behavior, architecture, tests, data flows, active ownership, operational constraints, and unfinished work. Name supporting files/revisions or observations and distinguish verified state, reported facts, assumptions, and unknowns. A scaffold, old note, or successful mock is not evidence that a deployed system works. Resolve inexpensive uncertainties with bounded reads; ask only about consequential behavioral choices or real permission boundaries, while continuing independent work.

State the desired outcome and first useful version, exclusions, constraints, and settled/open decisions. Compare an alternative only where it affects a decision. Describe target components and interfaces; name each source of truth, editing authority, cache/projection, shared contract, and integration owner. Include failure, identity, concurrency, migration, recovery, or access semantics only where relevant. Retain existing services and another writer's work unless changing them is authorized.

## Make work assignable

Create stable task IDs with a concrete output, owner role, phase/workstream, predecessor IDs, non-task prerequisites, and observable acceptance criteria. Use roles when people are unassigned. Keep mandatory work separate from optional extensions; identify the target milestone that defines the first useful release. Dependencies express actual prerequisites, not merely a preferred ordering. Model a real approval/evidence gate as a task with explicit exit criteria; keep external access/sample/decision prerequisites visible instead of inventing a satisfied node.

Identify safe parallel branches and their join points. One writer owns each shared contract, schema, migration sequence, entrypoint, or live state transaction. Separate checkouts do not make shared refs, databases, or production state independent. Assign integration and merge order; consumers use a frozen contract/fixture baseline. Route a contract change through its owner, then revise affected tasks and checks. A failed review or compatibility check triggers a replan; do not add a backward edge to the dependency DAG.

Cover milestone gates, risks with mitigations/owners, and decisions with their impact and latest useful decision point. Include acceptance and operational handoff/recovery only where the implementation needs them. Do not replicate a previous project's gate count or private details.

## One source for prose and dependencies

For a substantial plan, read [the source format](references/plan-source.md). Write task-owned `plan.json`; it is the authority for task metadata, dependencies, milestones, and planning narrative. Generate `plan.md`, `dependencies.md`, and `dependencies.html` together:

```sh
uv run --no-project <skill-dir>/scripts/plan.py plan.json --out <task-owned-output-dir>
```

Use a writable uv cache if the default cache is restricted. The helper has no third-party Python dependencies. It rejects missing/duplicate nodes, invalid fields, cycles, and required targets depending on optional work before rendering. It calculates a duration-based critical path only with complete relevant estimates; otherwise it reports a structural dependency chain, explicitly not a schedule. No calendar promise follows from either: resource contention, approval waits, and uncertainty still need judgment. `--check` validates without writing.

Edit the JSON and regenerate every view whenever tasks change. Never maintain a second hand-written task table or graph; narrative may reference task IDs. Keep generated outputs together with the source and label them as snapshots. The text view includes an adjacency list, topological readiness layers, and a static Mermaid fallback. Review the meaningful edges and external prerequisites: graph validity alone cannot prove a feasible plan.

## Interactive dependency view

Use the available **visualize** skill/plugin for the in-conversation dependency view; read its full current `SKILL.md` before presenting or adapting the fragment. Discover it from the active skill catalog rather than hard-coding a plugin cache/version. The bundled fragment template follows its native controls and theme conventions and has no network requests. Generate it from the same JSON as the prose. Show task detail, predecessor/successor highlighting, critical-chain markers, and phase/workstream filters where the data offers multiple choices. Filtering never changes the graph analysis; show hidden counts and keep full prerequisites in detail.

When Visualize is supported, return the generated fragment using its documented content reference and absolute writable task-owned path. Inspect it using the plugin's local render helper/browser where available: selecting a task must update details and relation labels, filtering must not suggest hidden prerequisites vanished, and narrow layouts/keyboard controls must work. For large graphs, use a selected subgraph or text view rather than compressing unreadable nodes. If Visualize or browser inspection is unavailable, say which capability is missing and provide `dependencies.md`/Mermaid and the generated local fragment. Do not install, upload, host, or publish anything merely to display a plan.

Finish with the outcome, source/output locations, unresolved decisions, and the next ready work or true gate. Distinguish planned, implemented, and verified work. Keep private examples and source evidence in the task's authorized storage.
