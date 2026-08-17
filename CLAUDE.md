# AI Coding Rules — AppX Manager

Behavioral guidelines to reduce common LLM coding mistakes.
**Tradeoff:** bias toward caution over speed. For trivial tasks (typo fixes, obvious one-liners), use judgment.

## 1. Think Before Coding
Don't assume. Don't hide confusion. Surface tradeoffs.
- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First
Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Test: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes
Touch only what you must. Clean up only your own mess.
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

Test: Every changed line should trace directly to the request.

## 4. Goal-Driven Execution
Define success criteria. Loop until verified.
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure behaviour holds before and after"

For multi-step tasks, state a brief plan with a verify step per step:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```
Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

**AppX Manager-specific note:** there IS an automated test suite (`AppX ManagerTests`, Swift
Testing), but it's narrow — only `GemScanner` parsing and `HomebrewScanner`'s JSON decoder are
covered. "Write a test, then make it pass" applies as-is only within that surface; for
everything else (the other 4 scanners, all 5 updaters, `ScanEngine`, all UI), see
`AI-Context/SDLC.md` § "What 'verify' means in this codebase" for what to do instead (build
success + a real manual run, checking the app's own debug log).

---

## This repo uses an AI-Context memory system

Before working on any task in this repo, read in this order:
1. `AI-Context/INDEX.md` — the map of what exists + feature status.
2. `AI-Context/architecture.md` — what the app is (single consolidated file, use its table of contents).
3. `AI-Context/SDLC.md` — how we work, conventions, and where files go.
4. The relevant `AI-Context/features/*.md` for the feature you're touching (if one exists yet).

**After completing any change**, run the `update-context` prompt (Copilot: `/update-context`;
otherwise follow `AI-Context/prompts/update-context.md`) to update the relevant feature file and
the status table in `INDEX.md`. This is part of definition-of-done (see `AI-Context/SDLC.md`).
Stale context is worse than none.
