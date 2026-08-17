# AI-Context — Index

This folder is the **AI memory layer** for AppX Manager. It exists so any AI assistant, in any
IDE, starts each session already knowing the system instead of being re-explained. Keep it
current: updating it after each iteration is part of definition-of-done (see [SDLC.md](SDLC.md)).

**What AppX Manager is:** a native macOS app that gives you one dashboard to see and update
everything installed on your Mac — App Store apps, direct-download apps, Homebrew
formulae/casks, and global npm/pip/gem packages. See [architecture.md](architecture.md) for the
full quick-facts table.

## File map

| File | What it's for | When to read |
|---|---|---|
| `INDEX.md` (this file) | Map of what exists + feature status | First, every session |
| `architecture.md` | Deep, source-grounded architecture reference — one consolidated file | Before touching any area of the app |
| `SDLC.md` | How we work, coding conventions, where files go, what "verify" means here | Before writing or placing code |
| `features/<feature-name>.md` | Living, per-feature memory — created the first time that feature is actively worked on | When touching that feature |
| `features/_TEMPLATE.md` | Skeleton for creating a new feature file | When starting work on a feature with no file yet |
| `prompts/update-context.md` | The ritual to refresh this folder after a change | After any feature change |
| `../CLAUDE.md` / `../.github/copilot-instructions.md` | Behavioral coding rules (tool entry points) | Auto-loaded by tools |

## Read-first order

1. `INDEX.md` → 2. `architecture.md` (use its table of contents) → 3. `SDLC.md` → 4. the
relevant `features/*.md` (if one exists yet).

## Feature status

| Feature | State | Last updated |
|---|---|---|
| _(none yet)_ | — | — |

> Add a row per feature. States: `active` (in progress), `stable` (shipped, maintained),
> `experimental` (under evaluation), `parked` (paused). Don't pre-create files for features
> nobody is touching yet — see `prompts/update-context.md`. Candidate feature areas already
> identified in `architecture.md` § [Features](architecture.md#features): Homebrew scanning/
> updating, dev-tools (npm/pip/gem) scanning/updating, Mac App Store scanning/updating,
> direct-download detection (Sparkle + cask fallback + App Store homepage lookup), dashboard UI,
> onboarding, debug logging. None have a dedicated feature file yet as of this onboarding —
> create one the first time any of them is actively worked on again.

## How to extend

- New feature context → `features/<feature-name>.md` (copy `_TEMPLATE.md`), then add a status
  row above.
- Substance never goes in the tool entry files (`CLAUDE.md`, `copilot-instructions.md`) —
  those hold only behavioral rules + a pointer here.
