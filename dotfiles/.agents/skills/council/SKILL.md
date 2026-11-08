---
name: council
description: Use when Ezra explicitly asks for a multi-provider council review.
---
# Council

Before review, address known issues and run the relevant focused checks. Give reviewers the current diff and the user's actual request. In T3 Code, inspect `orchestrator_capabilities` and use supported delegates. Prefer one strong model from each of three available providers at high reasoning effort, unless Ezra names reviewers. If three providers are unavailable, report which are available; do not silently substitute. Keep each review read-only and independent.

Ask for concrete correctness, regression, and scope findings with file and line references. For code review, request a score out of 10, but do not treat scores or reviewer agreement as proof. Reconcile findings against the source and checks. Fix only supported, in-scope issues; decline nits and scope creep with concise reasons. If fixes change behavior, request fresh review of that diff when useful and within the user's requested scope.

Summarize useful findings, disagreements, round count, reviewers actually used, and remaining checks. If there is a PR, put the result in its description only when the user asked for that or it is part of the requested PR workflow; do not post a comment just to report the council.
