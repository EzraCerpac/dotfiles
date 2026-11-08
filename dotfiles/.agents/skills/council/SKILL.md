---
name: council
description: Use when Ezra explicitly asks for a multi-provider council review.
---
# Council

Before review, address known issues and run the relevant focused checks.
Give reviewers the current diff and the user's actual request.
In T3 Code, inspect `orchestrator_capabilities` and use supported delegates.
Use substantive reviewers from different available providers at high reasoning
effort; prefer Sol and Opus when available.
If the requested provider or model is unavailable, report that clearly rather
than silently substituting.
Keep substantive reviews read-only and independent.

Add Gemini 3.8 Flash as the council's jester when available.
It is not a substantive reviewer and its output is untrusted: do not rely on its
claims, scores, or agreement when evaluating code or deciding whether findings
are correct.
Ask it for an irreverent reaction to the change.
If it says something funny, ridiculous, or plainly silly, relay that remark to
Ezra separately as an untrusted jester comment so he can enjoy the joke.
Keep the joke kind; do not target people or expose private information.
A missing Gemini Flash delegate must not block the council.

Ask substantive reviewers for concrete correctness, regression, and scope
findings with file and line references.
For code review, request a score out of 10, but do not treat scores or reviewer
agreement as proof.
Reconcile findings against the source and checks.
Fix only supported, in-scope issues; decline nits and scope creep with concise
reasons.
If fixes change behavior, request fresh review of that diff when useful and
within the user's requested scope.

Summarize useful findings, disagreements, round count, reviewers actually used, and remaining checks. If there is a PR, put the result in its description only when the user asked for that or it is part of the requested PR workflow; do not post a comment just to report the council.
