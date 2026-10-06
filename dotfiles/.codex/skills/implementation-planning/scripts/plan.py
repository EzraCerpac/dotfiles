#!/usr/bin/env python3
"""Validate a planning DAG and render its synchronized prose/text/Visualize views."""
import argparse
import html
import json
import math
import re
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def string(value, label):
    require(isinstance(value, str) and bool(value.strip()), f"{label}: nonempty string required")


def strings(value, label, nonempty=False):
    require(isinstance(value, list), f"{label}: list required")
    require(not nonempty or bool(value), f"{label}: cannot be empty")
    for item in value:
        string(item, label)


def analyze(plan):
    require(isinstance(plan, dict), "plan must be an object")
    require(type(plan.get("schema_version")) is int and plan["schema_version"] == 1,
            "schema_version must be 1")
    for field in ("title", "status"):
        string(plan.get(field), field)
    string(plan.get("duration_unit", "effort units"), "duration_unit")
    require(isinstance(plan.get("sections"), list), "sections: list required")
    for section in plan["sections"]:
        require(isinstance(section, dict), "section must be an object")
        for field in ("title", "body"):
            string(section.get(field), f"section {field}")
    tasks = plan.get("tasks")
    require(isinstance(tasks, list) and bool(tasks), "tasks: nonempty list required")
    nodes = {}
    for task in tasks:
        require(isinstance(task, dict), "task must be an object")
        for field in ("id", "title", "owner", "phase", "workstream"):
            string(task.get(field), f"task {field}")
        key = task["id"]
        require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,39}", key), f"invalid task ID: {key}")
        require(key not in nodes, f"duplicate task: {key}")
        for field in ("deliverables", "acceptance", "depends_on", "prerequisites"):
            strings(task.get(field), f"{key}.{field}", field in ("deliverables", "acceptance"))
        require(len(set(task["depends_on"])) == len(task["depends_on"]), f"{key}: duplicate dependency")
        require(type(task.get("optional", False)) is bool, f"{key}: optional must be boolean")
        require(task.get("kind", "task") in ("task", "gate"), f"{key}: invalid kind")
        duration = task.get("duration")
        require(duration is None or (type(duration) in (int, float) and math.isfinite(duration)
                                     and duration >= 0), f"{key}: invalid duration")
        nodes[key] = task
    successors = {key: [] for key in nodes}
    for key, task in nodes.items():
        for pred in task["depends_on"]:
            require(pred in nodes, f"{key}: missing predecessor {pred}")
            successors[pred].append(key)
    targets = plan.get("target_ids")
    strings(targets, "target_ids", True)
    require(len(set(targets)) == len(targets), "duplicate target_ids")
    for key in targets:
        require(key in nodes, f"missing target: {key}")
    milestones = plan.get("milestones", [])
    require(isinstance(milestones, list), "milestones must be a list")
    milestone_ids = set()
    for milestone in milestones:
        require(isinstance(milestone, dict), "milestone must be an object")
        for field in ("id", "title", "owner"):
            string(milestone.get(field), f"milestone {field}")
        require(milestone["id"] not in milestone_ids, "duplicate milestone ID")
        milestone_ids.add(milestone["id"])
        strings(milestone.get("acceptance"), "milestone acceptance", True)
        strings(milestone.get("depends_on"), "milestone depends_on", True)
        for key in milestone["depends_on"]:
            require(key in nodes, f"milestone: missing task {key}")
    indegree = {key: len(task["depends_on"]) for key, task in nodes.items()}
    order, layers = [], []
    ready = [key for key in nodes if indegree[key] == 0]
    while ready:
        layers.append(ready)
        order.extend(ready)
        next_ready = []
        for key in ready:
            for child in successors[key]:
                indegree[child] -= 1
                if indegree[child] == 0:
                    next_ready.append(child)
        ready = next_ready
    require(len(order) == len(nodes), "cycle detected among: " + ", ".join(k for k in nodes if indegree[k]))
    relevant = set(targets)
    for key in reversed(order):
        if key in relevant:
            relevant.update(nodes[key]["depends_on"])
    require(not any(nodes[k].get("optional", False) for k in relevant),
            "required target depends on optional work; revise scope/dependencies")
    timed = all(nodes[k].get("duration") is not None for k in relevant)
    finish, best_pred, start = {}, {}, {}
    for key in order:
        if key not in relevant:
            continue
        preds = nodes[key]["depends_on"]
        pred = max(preds, key=lambda p: finish[p]) if preds else None
        best_pred[key] = pred
        start[key] = finish[pred] if pred else 0
        finish[key] = start[key] + (nodes[key]["duration"] if timed else 1)
    end = max(targets, key=lambda key: finish[key])
    total = finish[end]
    chain = []
    key = end
    while key is not None:
        chain.append(key)
        key = best_pred[key]
    chain.reverse()
    critical, critical_edges, slack = set(chain), [], {}
    if timed:
        latest = {}
        for key in reversed(order):
            if key not in relevant:
                continue
            next_starts = [latest[c] for c in successors[key] if c in relevant]
            if key in targets or not next_starts:
                next_starts.append(total)
            latest[key] = min(next_starts) - nodes[key]["duration"]
            slack[key] = latest[key] - start[key]
        critical = {key for key in relevant if abs(slack[key]) < 1e-8}
        critical_edges = [[p, c] for p in order for c in successors[p]
                          if p in critical and c in critical and abs(finish[p] - start[c]) < 1e-8]
    else:
        critical_edges = [list(pair) for pair in zip(chain, chain[1:])]
    return dict(order=order, layers=layers, successors=successors, chain=chain,
                critical=[k for k in order if k in critical], critical_edges=critical_edges,
                mode="duration" if timed else "structural", total=total,
                relevant=[k for k in order if k in relevant], slack=slack)


def md(value):
    return str(value).replace("\n", " ").replace("|", "\\|")


def summary(plan, graph):
    chain = " → ".join(graph["chain"])
    if graph["mode"] == "duration":
        return (f"Critical path (one representative): {chain}; {graph['total']:g} "
                f"{plan.get('duration_unit', 'effort units')}. Zero-slack tasks: "
                + ", ".join(graph["critical"]) + ". Estimates exclude unmodeled resource/external waits.")
    return f"Structural dependency chain: {chain}. Durations are incomplete; this is not a time-based critical path or schedule."


def render_text(plan, graph, source):
    nodes = {task["id"]: task for task in plan["tasks"]}
    lines = [f"# {plan['title']} — dependencies", "", f"Generated snapshot from `{source}`; edit the source and regenerate.",
             "", summary(plan, graph), "", "Edges: predecessor → dependent. Layers show dependency readiness, not resource availability.",
             "", "## Readiness layers", ""]
    lines.extend(f"- {i + 1}: " + ", ".join(layer) for i, layer in enumerate(graph["layers"]))
    lines.extend(["", "## Predecessors and external prerequisites", ""])
    for key in graph["order"]:
        task = nodes[key]
        lines.append(f"- {key} — {md(task['title'])}; needs: " + (", ".join(task["depends_on"]) or "none")
                     + "; external: " + ("; ".join(map(md, task["prerequisites"])) or "none")
                     + ("; optional" if task.get("optional") else ""))
    lines.extend(["", "## Static diagram", "", "```mermaid", "flowchart TD"])
    keys = {key: f"n{i}" for i, key in enumerate(graph["order"])}
    for key in graph["order"]:
        task = nodes[key]
        label = html.escape(key + " " + task["title"], quote=True).replace("\n", " ").replace("`", "&#96;")
        lines.append(f'  {keys[key]}["{label}"]')
    for key in graph["order"]:
        for pred in nodes[key]["depends_on"]:
            lines.append(f"  {keys[pred]} --> {keys[key]}")
    lines.extend(["```", ""])
    return "\n".join(lines)


def render_plan(plan, graph, source):
    lines = [f"# {plan['title']}", "", f"Status: {plan['status']}", "",
             f"Generated snapshot from `{source}`; edit the source and regenerate.", ""]
    for section in plan["sections"]:
        lines.extend([f"## {section['title']}", "", section["body"], ""])
    lines.extend(["## Work packages", "", "| ID | Work / deliverables | Depends on / external prerequisites | Owner / acceptance | Phase / workstream |",
                  "| --- | --- | --- | --- | --- |"])
    nodes = {task["id"]: task for task in plan["tasks"]}
    for key in graph["order"]:
        task = nodes[key]
        flags = (" [optional]" if task.get("optional") else "") + (" [gate]" if task.get("kind") == "gate" else "")
        values = [key + flags, task["title"] + "; outputs: " + "; ".join(task["deliverables"]),
                  (", ".join(task["depends_on"]) or "none") + "; external: " + ("; ".join(task["prerequisites"]) or "none"),
                  task["owner"] + "; " + "; ".join(task["acceptance"]), task["phase"] + " / " + task["workstream"]]
        lines.append("| " + " | ".join(map(md, values)) + " |")
    lines.extend(["", "## Dependency analysis", "", summary(plan, graph), "",
                  "See [text dependencies](dependencies.md) and the interactive dependency view. External prerequisites remain separate from graph readiness.", ""])
    if plan.get("milestones"):
        lines.extend(["## Milestone exits", ""])
        for milestone in plan["milestones"]:
            lines.append(f"- {milestone['id']} — {milestone['title']}; owner: {milestone['owner']}; needs: "
                         + ", ".join(milestone["depends_on"]) + "; acceptance: " + "; ".join(milestone["acceptance"]))
    return "\n".join(lines) + "\n"


def render_fragment(plan, graph):
    template = (Path(__file__).resolve().parents[1] / "assets" / "dependencies.html").read_text()
    # Prevent authored values from terminating the JSON script block.
    payload = json.dumps(dict(plan=plan, graph=graph), ensure_ascii=True).replace("&", "\\u0026").replace("<", "\\u003c").replace(">", "\\u003e")
    require(template.count("__PLAN_DATA__") == 1, "template data slot missing/duplicated")
    fragment = template.replace("__PLAN_DATA__", payload)
    require(len(fragment.encode()) < 1_000_000, "fragment exceeds Visualize 1 MB limit; split the plan")
    return fragment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        plan = json.loads(args.source.read_text())
        graph = analyze(plan)
        if args.check:
            print(f"Valid DAG: {len(plan['tasks'])} tasks, {len(graph['layers'])} readiness layers. " + summary(plan, graph))
            return
        require(args.out is not None, "--out is required unless using --check")
        source = str(args.source.resolve())
        outputs = {"plan.md": render_plan(plan, graph, source),
                   "dependencies.md": render_text(plan, graph, source),
                   "dependencies.html": render_fragment(plan, graph)}
        require(args.source.resolve() not in {(args.out / name).resolve() for name in outputs}, "output would overwrite source")
        args.out.mkdir(parents=True, exist_ok=True)
        for name, content in outputs.items():
            (args.out / name).write_text(content, encoding="utf-8")
        print(f"Rendered {len(plan['tasks'])} tasks to {args.out.resolve()}")
    except (ValueError, OSError) as error:
        parser.exit(2, f"Plan error: {error}\n")


if __name__ == "__main__":
    main()
