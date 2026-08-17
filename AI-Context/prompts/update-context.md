# Prompt: update-context

> Invoke after finishing or changing any feature work, before moving on / before committing.
> In Copilot: type `/update-context` (VS Code discovers the wrapper at
> `.github/prompts/update-context.prompt.md`, which delegates to this file).
> In other tools: paste this file's body as the instruction.
>
> **Scope guard: this prompt edits only `AI-Context/**` and the tool rule files (`CLAUDE.md`,
> `.github/copilot-instructions.md`) inside this repo (`AppX Manager/`) — never the app's own
> source, and never the outer `AppsUpdater/` workspace folder's own files.**

You are updating the AI-Context memory layer so it matches the code that now exists.

## Steps

1. **Identify what changed and where.** From the current diff / staged changes / the feature
   just worked on, determine which feature in `AI-Context/features/` is affected. If none
   exists yet, create `AI-Context/features/<feature-name>.md` from
   `AI-Context/features/_TEMPLATE.md`.

2. **Verify against live source — do not trust prose.** Read the actual changed files. Then
   **rewrite the feature file in its entirety** — replace the complete content from the
   `# Feature:` title to the last line of the Verification log. Do not patch individual
   sections; a full rewrite ensures no stale content survives. Update **Current State**,
   **Architecture**, **Key Paths**, and **Invariants** to match what the code now does. Replace
   any claim the code contradicts. Keep file/class names; drop volatile line numbers/LOC counts
   (see `SDLC.md`).

3. **Promote / retire.** If an experiment became permanent, move it from a note into
   **Invariants**. If something was tried and abandoned, add a one-line entry to **What Didn't
   Work** (keep that section forever — it's the guardrail against re-attempting dead ends).
   Never silently delete a "What Didn't Work" entry.

4. **Update Open Items.** Mark resolved items done; add any new follow-ups discovered. Mark
   anything you couldn't independently verify as `(unverified)`.

5. **Update `INDEX.md`.** Set the feature's status row (`active`/`stable`/`experimental`/
   `parked`) and the last-updated date to today.

6. **Update `architecture.md` if it's gone stale.** If the change affects something asserted in
   `architecture.md` (a Quick Fact, a design pattern, a Legacy Note), correct it there too —
   `architecture.md` is a snapshot, and a wrong snapshot is worse than an old one.

7. **Report, don't commit.** Print: which files you edited (all should be under `AI-Context/`,
   or `CLAUDE.md`/`.github/copilot-instructions.md`), which claims changed because the code
   disagreed with the old doc, and anything you couldn't verify (mark `(unverified)`). Stop for
   human review before these changes are committed/pushed.

## Rules

- This prompt edits **only** `AI-Context/**` and the tool rule files (`CLAUDE.md`,
  `.github/copilot-instructions.md`) in this repo — never AppX Manager's own app source, and
  never the outer `AppsUpdater/` workspace folder.
- Capture invariants and decisions, not volatile implementation detail.
- If the code and an existing doc claim conflict, the code wins and the doc is corrected.
