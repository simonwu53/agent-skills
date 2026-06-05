# GEMINI.md

Guidance for Gemini / Antigravity (and other coding agents) working in this repository.

This repo is a **personal skill manager**: it collects agent skills into `skills/` and
installs them (via symlinks) into agent tool directories. The entry point for every
operation is `main.sh`. See [README.md](README.md) for the full user-facing usage.

---

## Coding Guidelines

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it. But don't oversimplify the code to the point that it becomes unreadable or hard to maintain.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify it.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

### 4. Other Guidelines

- When reading a dataset file, always read the file header first (or first few rows) to understand the structure and schema. This applies to parquet, csv, geojson, gpkg, etc.
- When testing or validating in the command line, make output as concise as possible. Only target the specific information that you need.

---

## Project Conventions

- **Bash first.** Implement features in Bash (Zsh-compatible). Only reach for Python
  (via `uv`, venv at `.venv`, deps via `uv add`) if Bash genuinely cannot do it — and the
  entry point must still be `main.sh`.
- **No new tools.** Use only tools already available in the user's shell (`git`, `curl`,
  `unzip`, `rsync`, etc.). Do not install anything without the user's explicit agreement.
- **macOS Bash 3.2 compatibility.** Avoid Bash 4+ features (associative arrays,
  `${var,,}`, `mapfile`). Use indexed arrays / `case` / `tr` instead.
- **Keep `main.sh` as the single entry point.** It parses the operation and dispatches to
  `src/download.sh`, `src/install.sh`, or `src/remove.sh`, all sharing `src/common.sh`.
- **Validate skills by `SKILL.md`.** A directory is a skill only if it contains `SKILL.md`.
- Put validation/smoke tests under `test/`.

## How operations behave (must stay true)

- **Destructive actions confirm first.** Clearing a target skills directory on install,
  and any removal, must prompt the user with a `y/n` confirmation. Prompts read from the
  terminal — never run them inside a piped `while read` loop (it steals stdin); iterate
  with newline-`IFS` `for` loops instead (see `install.sh` / `remove.sh`).
- **Install creates symlinks**, never copies, so the repo stays the single source of truth.
- **Default category is `Main`** when `--cat`/`-c` is omitted; create it if missing.
- **Default scope is global, default tool set is all three** (claude, antigravity,
  antigravity-ide) when not narrowed by a flag. `-p`/`--path` switches to project scope
  (value optional → current dir).
- **Pins persist across installs.** `--pin` records a skill in `config.yaml` *and*
  symlinks it now; after every install-clear, pinned skills are re-linked, so they survive
  even without `--keep`. `--unpin` drops the config entry and its symlinks.
- **Remove/unload read `config.yaml` first.** If a removal (or `--unload`) targets a pinned
  skill, warn the user, confirm, and only then delete — also stripping the matching pin
  entry. (A category-level pin covering a single-skill removal is left intact; tell the
  user to `--unpin` the category.)
- **`--unload` deletes the repo source** (inverse of `--load`) — destructive, so confirm
  first. It removes empty category dirs and warns that any existing symlinks will dangle.
- **`config.yaml` is machine-local.** Auto-created at repo root on every run, git-ignored
  (it stores absolute project paths). Structure is namespaced + versioned (`version:`,
  `pins:`) so future features add their own top-level section; the pins writer splices only
  the `pins:` block and preserves the rest.

## Version Control

- **Only touch version control when asked.** Do commits, merges, pushes, pull requests,
  branch deletions, etc. *only* when the user explicitly requests them. The user decides
  when to update the workspace or push to the origin. Otherwise, just do the job the user
  asked for and leave version-control actions alone.
- **Never commit straight to `main`.** Gemini / Antigravity works on the `gemini_space`
  branch; other agents use `{agent_name}_space` (e.g. Claude → `claude_space`). Branch off
  the latest `main` if the working branch doesn't exist yet.
- **`main` advances one squashed commit per update.** When the user asks to push updates
  to the remote, squash every commit on the working branch into a single commit on `main`
  (`git checkout main && git merge --squash <branch> && git commit`). `main` only ever
  moves forward by one summarized commit at a time — never a string of working commits.
- **Delete the working branch after `main` is updated.** Once the squashed commit is on
  `main` and pushed, the old working branch can be safely removed (local and remote);
  start the next round of work from a fresh branch off `main`.
- **The squashed commit message is a changelog entry.** Write a proposed title line, then
  a concise bulleted summary of what changed. Keep it tight, not wordy.
- **Versioning is `major.minor.patch`** (e.g. `1.0.0`), bumped in the changelog title:
  - **patch** — bug fixes / small corrections.
  - **minor** — additive changes, e.g. a new skill.
  - **major** — significant changes: new features, source-code refactors, breaking changes.

## Interacting with the user

- When a request maps onto an existing operation, prefer running `main.sh` over ad-hoc
  commands, so behavior (confirmations, symlinks, category defaults) stays consistent.
- Before downloading from a URL the user gave, confirm whether it's a whole-repo link
  (and whether it needs `--merge` vs `--cat`) or a single skill-folder link — the two
  take different flags.
- Report outcomes plainly: what was added/linked/removed and where. If something was
  skipped (e.g. missing `SKILL.md`, not a symlink), say so.

## Tool skill locations

| Tool             | Global (personal)                     | Project-scoped     |
|------------------|---------------------------------------|--------------------|
| Claude Desktop   | `~/.claude/skills/`                    | — (same as Code)   |
| Claude Code      | `~/.claude/skills/`                    | `.claude/skills/`  |
| Antigravity      | `~/.gemini/antigravity/skills/`        | `.agents/skills/`  |
| Antigravity IDE  | `~/.gemini/antigravity-ide/skills/`    | `.agents/skills/`  |
