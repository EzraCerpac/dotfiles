---
name: perch
description: Use Perch on explicit request for scoped semantic linting or high-volume screening against narrow criteria. Treat Jev results as advisory candidate flags for stronger-model or source verification. Use for a requested scan, targeted check, or existing finding; routine edits do not trigger it.
---

# perch

## Intended use

When configured for Jev, use it as a cheap, fast screening model for high-volume,
narrow semantic classification or linting. Keep each criterion explicit and bounded. Treat flagged
candidates as leads for a stronger model or direct source verification. This is the
user's intended role, not a measured accuracy or throughput claim.

Perch is code-oriented; arbitrary large text/record classification would use a
separate direct TypeSafe workflow. Do not set that up merely because this skill was
invoked. Perch is not the reviewer for subtle concurrency, distributed-sync races,
or nuanced architectural judgment. Do not attach it to Capd/Tinymist review or
set up SemBr linting unless the user later explicitly requests that work.

## This machine

Use `~/.local/bin/perch` from the repository being checked. This mise-managed
launcher preserves the current directory and supplies a private credential only
to the process. Do not print the key or put it in project `.env` files.

Run only the requested, bounded scan or check. Scope scans with `--paths` or
`--since`. Do not add automatic hooks, CI gates, a second-review ritual or mandatory
checks for routine edits. Findings remain advisory; verify flagged candidates
against source and, where appropriate, affected behavior.

The inspected installed package was Perch **0.4.1** on 2026-10-05. In that version,
the default route is Perch Cloud; an explicit `PERCH_BASE_URL` selects a direct
System One endpoint, such as TypeSafe. `PERCH_MODEL_ID` selects a model; the direct
client defaults to `jev-latest`. The effective runtime endpoint/model has not been
verified. Do not change it as part of using this skill or assume the private
credential proves the endpoint. Prefer installed CLI/source documentation if the
package version changes.

A scan or check sends selected source and context to the configured external
provider. Perch includes method source and nearby caller/callee context, bounded
to the request budget. `scan` reads the repository at **HEAD** and writes local
results/cache; `check` reads from **disk**, including uncommitted work, and does not
record a scan result. Both can make network requests. Provider/account billing
and data handling apply; this is not an offline check.

The examples below were adapted from the upstream **0.3.3** skill. Example costs,
request counts and output percentages are illustrations, not current pricing,
measured performance on this user's work, or calibrated defect rates. Use actual
reported usage and the selected provider's current terms when discussing cost.
Perch reports a model's probability, not proof that code is correct or defective.

## Scan what changed

```console
$ perch scan --since origin/main
checkout.py
  ID        Line  Severity  Type    Confidence  Problem      Method
  bdc67421    14  P1 (0.8)  defect         81%  wrong_order  place_order

✖ 1 problem in 1 file, all failing
perch at commit 5e9d910: 3 methods, read 3
3 requests  10k tokens in / 2k out  $0.0004
```

`--since <ref>` covers what changed since that ref in the HEAD snapshot;
uncommitted edits are outside that scan. `--paths a,b` covers named files or
directories. Add `--json` for full detail:
`perch scan --since origin/main --json`. Confirm the requested ref and scope.

Request volume depends on methods, context, rules and cache state. A repository
scan can be large; use the requested subset to check a bounded change.

Cached answers are reused when source, context, endpoint/model and question
wording match. A changed method, neighbour, model or rule can require new requests;
do not promise that a rescan is free or almost free.

| Exit | |
| --- | --- |
| `0` | Command completed; scan/check reported no issue affecting its exit status. |
| `3` | Scan/check found issues affecting its exit status; they remain advisory. |
| `1` | Command failed or some methods/rules could not be read after retrying. |
| `2` | Invalid arguments or a setup overwrite needs explicit force. |

`3` is a result rather than an error, so report what it found. Only `1` and `2` are
failures.

## Read the JSON

Use `--json` on supported report-producing commands. The table is rounded off for
a terminal, and the JSON carries the detail.

```console
$ perch issues
ID        Method             Location           Type      Kind                    Severity
05a5b5bd  scanRepository     src/scan.js:129    refactor  too_big 98%             -
b2d0885f  formatFinding      src/report.js:376  refactor  too_big 98%             -
990c94ac  scan               src/cli.js:350     refactor  too_big 92%             -
```

`perch issues <id> --json` gives one finding in full. Every question's answer carries
the distribution behind it:

```json
"has_bug": 0.46,
"kind": { "choice": "missing_null_handling", "probability": 0.84,
          "probabilities": { "missing_null_handling": 0.84, "wrong_return": 0.08, "boundary": 0.04 } },
"severity": { "level": "P2", "score": 1.4, "confidence": 0.38,
              "probabilities": { "0": 0.09, "1": 0.43, "2": 0.47, "3": 0.01 } }
```

## Reading a finding

A finding is an advisory drawn from a probability and a rule. It does not locate a
defect for you.

The number is model belief, not a verified defect rate. How bad the problem would
be is a separate field.

Probabilities spread across several kinds can signal an ambiguous classification;
they do not establish that a defect exists. Read the method and verify the claim
before adopting a label.

A reported location has its own confidence and may be imprecise. Treat it as a
navigation hint. Neither a location nor a percentage proves a nearby defect.

Answers below a question's `min` stay out of the report and stay in the JSON. A 56%
`secret_exposure` is worth a look while the report is silent about it.

Read the code before you change it. Close a finding when the code is right. Never
rewrite working code to satisfy a probability.

## Check one method

After a fix, ask about the thing you changed.

```console
$ perch check src/store.js::openStore.scanDir
src/store.js:74  openStore.scanDir
5 checks, 0 broken.

  Also raised: does_not_do_what_it_claims 80%
2 requests  5k tokens in / 767 out  $0.0002
```

`perch check src/store.js::openStore.scanDir --json` gives the reading in full,
and an issue id works in place of a target. `--rules <name>` restricts the check to
an existing narrow rule rather than asking every applicable question.

This reads the file off disk, so it works on uncommitted code. It makes an external
model request but does not record a scan result or update/close the stored issue.
Exit `3` means it reported an issue affecting exit status, not that the issue has
been independently verified.

## Close a finding you have judged

```console
$ perch close 05a5b5bd --reason "the walk is one job read top to bottom"
05a5b5bd  scanRepository  src/scan.js:129  closed  too_big
```

A close covers the kinds the issue was listing. A different problem found on that
method later is still reported. `--kind too_big` closes one kind and leaves the rest
open.

Always give a reason. That is what the next person reads instead of reopening it.

## Write a rule when a mistake repeats

Add or edit persistent repository rules only when that setup is requested or
already authorized. An ordinary scan/check request does not itself authorize
new rules. A recurring issue can suggest a narrow rule for later use.

```console
$ perch rules add no-silent-failure --where "src/**/*.js" --each method \
    --ensure "Errors are returned or raised. Catching one, logging it, and carrying on as though it succeeded breaks this."
Added no-silent-failure.
```

`--where` takes a glob. `--each` is `file`, `method` or `test`. `--min N` sets a floor
for that rule alone. `--gate no` reports a rule without failing runs.

`--ensure_absent` is for a claim about the codebase as a whole. It searches the
likeliest places and stops at the answer.

Rules can share a method request. They may be split across requests when model
limits or the context budget require it; do not assume any number of rules is free.

Say what breaks a rule and what satisfies it. A rule answering in the sixties about
everything cannot tell anything apart. Reword it or drop it. Raising its floor until
it keeps nothing is turning it off with extra steps.

`perch rules list` shows every rule and question in force, and whether each fails a run.

## Tune a rule until it tells two things apart

A rule is a sentence put to a model, so a new one is a draft. Test it against two
inputs before you trust it. One should pass. The other is a copy you broke in the way
the rule is meant to catch.

`perch check <path> --rules <name>` reads off disk and makes a model request. Keep
validation bounded; cost and latency depend on the selected provider, input size
and request count.

The gap between the two readings is the rule's whole value. A rule that answers about
the same on both is measuring something other than what it says.

The upstream examples below illustrate rule design, not measured performance on
this user's files. Two controls can reveal a bad rule; they do not establish
calibration or general accuracy.

**Too broad.** A file rule worded as a universal gets you there. "Every sentence is
short" asks whether a counterexample exists anywhere in the file. Those odds rise with
the file's length whatever the prose does. Three rules written that way over this
project's docs ranked ten pages in almost exactly their line order. One page rewritten
entirely in 34-word run-ons read 92%. The same page in short sentences read 88%. Four
points between opposites.

**Too narrow.** Reworded to hunt the single longest sentence on a page, that rule
caught both broken controls. It also fired 80% on a clean page. On a long page there
is always some sentence to object to.

**The middle.** Name a bounded part of the file and judge only that. "Read the first
four prose paragraphs" and "find the first block that runs a real `perch` command"
both work. What they ask about does not grow with the page. The same three rules then
read 84%, 79% and 95% against their broken controls, and passed every clean page.

Aim for a gap that wide. A pass and a fail within a few points of each other means the
rule needs another pass.

## Other commands

| | |
| --- | --- |
| `perch doctor` | Whether perch can run here, and what the last run asked. |
| `perch issues --types` | Everything `--filter` accepts. |
| `perch --version` | The version in use. |
