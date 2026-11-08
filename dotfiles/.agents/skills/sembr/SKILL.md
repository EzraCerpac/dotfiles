---
name: sembr
description: >-
  Apply semantic line breaks to requested formatting-only passes or prose
  being added or edited in .md, .markdown, or .rst files. Perform authorized
  wording edits first, then format only the changed prose. Formatting-only
  passes preserve wording and rendered output. Respect the local line-break
  style, untouched paragraphs, no-touch regions, and explicit opt-outs.
---

# sembr

Format prose so its physical line structure mirrors its semantic structure,
per the Semantic Line Breaks specification at https://sembr.org/.
For normal prose edits, perform the authorized wording change first,
then apply formatting to the changed prose.
The formatting baseline is that edited text;
for a formatting-only request, the baseline is the original text.
All wording and rendered-output invariants below apply to the formatting phase.
Follow the mode's local-style and scope rules;
within that scope, never silently skip or relax a MUST rule.

## Modes

### Explicit reformat

The user asked to reformat existing text
(e.g. "format with sembr", "apply semantic line breaks",
"оформи по sembr", or "перепиши по sembr").
Preserve every word and the rendered output of the original target.
Apply MUST/SHOULD/MAY rules to the targeted prose
(snippet, file, or section).
Reformat fully within the target;
do not touch surrounding paragraphs.

### Default-on-edit

Use after authorized prose creation or wording edits
in `.md`, `.markdown`, or `.rst` files;
a separate formatting request is unnecessary.
Complete the requested wording edit first,
then format only the changed prose against that edited baseline.
Formatting itself must add no wording or rendered-output change.
The guiding principle:
**only the part being edited gets sembr-shaped;
everything else stays byte-identical.**

- **New prose** (new file, new paragraph, freshly inserted block):
  write in sembr from the start.
- **Edits inside an existing paragraph:**
  match the paragraph's existing line-break style.
  If it already follows sembr
  (multiple short lines, breaks after sentence terminators or clauses); 
  keep sembr in your edit.
  If it is one long line, hard-wrapped at a fixed column,
  or follows another visible convention; 
  match that convention.
  If the paragraph is too short to tell; 
  default to sembr.
  Preserve untouched prose spans within the paragraph.
  In this mode, the existing paragraph's line-break convention takes
  precedence over the generic sentence and clause breaking rules.
- **Untouched paragraphs:**
  never reformat.
  Editing one paragraph
  must not change line breaks, spacing, or wording in any neighbour.
  Diffs must stay localised to the edited region.
- **Opt-out:**
  if the user says
  «не применяй sembr здесь» / «don't apply sembr here»
  (or sets a project-level preference); 
  follow the file's existing convention instead.

### When NOT to use

Skip both modes for plain `.txt`,
GFM with `<br>` line-break behavior,
email,
chat (Slack, Telegram, Discord),
or any context where single newlines render as visible breaks.
Sembr there would change the rendered output and violate rule 2.
Authorized wording edits may still proceed without Sembr.

## Inputs

Identify the target before editing:
- A snippet pasted in the conversation → return the reformatted text.
- A file path or section in a file → edit the file in place.
- During formatting, preserve document structure and rendering
  (headings, lists, code blocks, links, inline markup).

Sembr applies only to prose paragraphs
and prose-bearing list items and blockquotes.
**No-touch regions**;
during Sembr formatting, never modify whitespace,
line breaks,
or any content inside:
- fenced code blocks (` ``` `) and indented code blocks;
- inline code spans (`` ` ``);
- HTML islands;
- Markdown tables;
- YAML / TOML frontmatter;
- reST line blocks (lines starting with `|`);
- reST directives (`.. name::` and their indented content);
- reST literal blocks (after a trailing `::`, until dedent);
- reST grid and simple tables;
- reST doctest blocks (lines starting with `>>>`).

If the target is ambiguous, ask before editing.

## Rules

### MUST (mandatory, no exceptions)

1. **Break after every sentence terminator**; `.`, `!`, `?`.
   A `.` is a terminator only when it ends a sentence; 
   not inside abbreviations (`e.g.`, `Mr.`, `U.S.`, `etc.`),
   version or dotted identifiers (`1.22.4`, `node.js`, `co.uk`),
   or ellipses (`…`, `...`).
   When in doubt,
   check the next character:
   if it starts a new sentence
   (capital letter after a space, or end of paragraph),
   break;
   otherwise do not.
2. **Formatting never alters wording or rendered output.**
   Compare against the formatting baseline:
   the original target for formatting-only,
   or the authorized edited text for normal prose edits.
   The visible result after rendering (Markdown, HTML, etc.)
   must be byte-identical to that baseline.
   The only allowed change is replacing an intra-paragraph space with
   a single newline
   (or vice versa).
   Forbidden:
   - adding, removing, or changing any non-whitespace character;
   - inserting or removing blank lines;
   - touching anything inside a no-touch region (see `Inputs`);
   - normalizing trailing whitespace, tabs, or blank-line counts.

   Verification:
   diff formatting baseline vs. formatted output; 
   only space ↔ newline swaps within prose paragraphs may appear.
3. **Never break inside a hyphenated word**
   (e.g. `state-of-the-art` stays on one line).

### SHOULD (apply unless they would violate a MUST rule or change meaning)

4. **Break after each independent clause**
   punctuated by `,`, `;`, `:`, or `; ` (em dash).
   Heuristic: an independent clause has a subject and a finite verb,
   and could stand alone as a sentence.
   «I went to the store, and I bought eggs»; 
   both sides are independent;
   break after the comma.
   «I went to the store to buy eggs»; 
   «to buy eggs» is dependent;
   no break.
   When the structure is genuinely ambiguous,
   leave the clause unbroken and surface the case in the report
   (see `Reporting`).
5. **Break before an enumerated or itemized list.**
6. **Keep lines under 80 characters.**
   When a line exceeds 80,
   break at the latest semantic boundary that satisfies the limit.

### MAY (use to improve readability or to satisfy MUST/SHOULD)

7. Break after a dependent clause for clarity or length.
8. Break between list items to group related entries.
9. Break before or after a hyperlink or inline markup.
10. Allow a line to exceed 80 characters
    when the overflow is an unbreakable unit
    (URL, code span, inline markup).

## Procedure

1. Read the input verbatim.
2. Confirm the rendering context.
   For `.md`, `.markdown`, `.rst`, `.html`,
   or contexts known to follow
   CommonMark / reST / standard HTML semantics,
   proceed.
   For plain text,
   GFM with `<br>` line-break behavior,
   email,
   chat (Slack, Telegram, Discord),
   or any context where single newlines render as visible breaks; 
   skip Sembr in both modes and state the rendering constraint.
   Authorized wording edits may still proceed.
   Sembr there would visibly change the output and violate rule 2.
3. In default-on-edit mode, make only the authorized wording change first.
   Use the edited prose as the formatting baseline.
   In explicit-reformat mode, use the original target as the baseline.
4. Apply MUST rules within the mode's local-style and scope rules.
5. Apply SHOULD rules wherever they don't conflict with a MUST rule
   or distort meaning.
6. Use MAY rules to fit the 80-character soft limit and improve readability.
7. During formatting, never paraphrase, reword, add, or remove content.
   If an optional structural break is ambiguous,
   leave that boundary unchanged and report the material exception.
8. Confirm formatting preserves the baseline's wording and rendered output.
   For a normal prose edit, also inspect the original-to-final diff
   to ensure wording changes stay within the authorized edit
   and untouched prose remains byte-identical.

## Examples

Bad; multi-clause line, no semantic structure:

```
The build pipeline succeeded; however, the deploy step failed because the secret rotated overnight, and we did not refresh the cache; so production is now serving stale config.
```

Good; sembr-formatted:

```
The build pipeline succeeded;
however, the deploy step failed because the secret rotated overnight,
and we did not refresh the cache; 
so production is now serving stale config.
```

Bad; break inside a hyphenated word (violates MUST rule 3):

```
This is a state-
of-the-art system.
```

Good:

```
This is a state-of-the-art system.
```

## Reporting

After editing,
state briefly which file or section was reformatted.
Do not quote the full reformatted text back to the user unless they
ask.

If any rule was relaxed or skipped during the pass; 
ambiguous independent clause left unbroken,
non-standard rendering context,
unbreakable line over 80 characters,
or any other place where the strict rules could not be applied
confidently; 
list each occurrence so the user knows where the result is best
effort rather than strict.
