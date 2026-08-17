# CLAUDE.md

Guidance for Claude (and other coding agents) working in this repository.

This repo is a **personal skill manager**: it collects whole source repos as git
submodules under `skills/repository/` (local sources under `skills/local/`), records
every loaded skill in `config.yaml` (the library database), and installs selected
skills into agent tool directories. The entry point for every operation is `main.sh`.
See [README.md](README.md) for the full user-facing usage.

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
  the op scripts in `src/` (`download.sh`, `install.sh`, `remove.sh`, `pin.sh`,
  `list.sh`, `sync.sh`), all sharing `src/common.sh` + `src/config.sh`.
- **Validate skills by `SKILL.md`.** A directory is a skill only if it contains `SKILL.md`.
- Put validation/smoke tests under `test/`.

## How operations behave (must stay true)

- **The library is repo-based.** `--load --link` accepts a GitHub repo **root** link only
  (`/tree/` subfolder links are rejected) and adds the repo as a git **submodule** at
  `skills/repository/<author>-<repo>/`. Skills stay inside their repo; `config.yaml`
  records each skill's repo slug + subpath, and install resolves the folder from there.
  Local sources (`--path`/`--file`) are stored under `skills/local/<name>/`. Loading
  stages `.gitmodules` changes but never commits.
- **Load auto mode** (no `--skill`): `SKILL.md` at the repo root → the repo is one skill;
  otherwise every subfolder of the repo's skills folder (`skills|skill|SKILLS|SKILL`) is
  a skill — **not** a category. Batch adds (2+) list the skills and confirm once.
  `--skill name` selects `skills/name`; `--skill Cat/name` selects `skills/Cat/name` and
  infers category `Cat` unless `--cat` overrides. `--merge` no longer exists.
- **Skill names are unique** (one name = one workflow). A load that clashes with an
  existing skill from a different source asks to replace the old one — double-confirmed
  (replace? then permanently delete?) — or skips the new skill. Same source → refresh.
- **Destructive actions confirm first.** Clearing a target skills directory on install,
  any removal/unload, and submodule removal must prompt with `y/n`. Prompts read from the
  terminal — never run them inside a piped `while read` loop (it steals stdin); iterate
  with newline-`IFS` `for` loops instead (see `install.sh` / `remove.sh`).
- **Install copies skills by default** (so tools that don't follow symlinks, e.g. Claude
  Desktop, can see them); `--symlink` opts into soft links pointing at the library. The
  same copy/symlink mode applies to pins re-installed during that install run.
- **Selectors are db-backed.** For install/remove/pin/unload, `--skill` takes skill
  names and/or category names (a category expands to all its skills; exact skill name
  wins on ambiguity, with a warning). `--skill` accepts multiple values everywhere.
- **`--update` is install that overwrites without prompting.** Plain `--install` warns and
  asks `y/n` before overwriting a skill that already exists in the target (declining skips
  just that skill). `--update` is the same operation (dispatches to `install_main`) but skips
  that per-skill prompt and only touches the named skill(s) — it implies `--keep`, so the
  rest of the target dir is left alone (no clear, no prompt).
- **Install state is recorded.** Each install/remove updates the skill's `agents`
  (global tools) / `projects` (project roots) fields in `config.yaml`.
- **`--list` shows skills.** With no tool flag or `-p`, it lists the library from
  `config.yaml` grouped by category (name, source slug, pin marker) — no directory
  scanning. With a tool flag (and/or `-p`) it lists the skills installed in that tool's
  skills dir, marking each `(copy)` or `(symlink)`.
- **Remove targets installed skill names.** **Omitting `--skill` removes every installed
  skill** for the targeted tool(s). Removal deletes a managed entry whether it's a
  symlink or a copied skill dir (one holding `SKILL.md`); a directory that isn't a
  managed skill is left untouched and reported. Removing a **pinned** skill warns,
  confirms, and unpins it (sets `pinned: false`).
- **Default category is `Main`** when `--cat`/`-c` is omitted.
- **Default scope is global, default tool set is all three** (claude, antigravity,
  antigravity-ide) when not narrowed by a flag. `-p`/`--path` switches to project scope
  (value optional → current dir).
- **Pins are a plain flag** (`pinned: true`). Every install-time clear re-installs all
  pinned skills into the cleared dir, so pins survive installs without `--keep`.
  `--unpin` only clears the flag — installed copies stay (use `--remove`).
- **`--unload` removes skills from the library** (inverse of `--load`) — destructive, so
  confirm first. Local sources are deleted; a repo submodule is removed (deinit +
  `git rm`) when its last skill is unloaded, behind its own confirm. Warns that existing
  symlinks will dangle.
- **`config.yaml` is the machine-local library db** (schema v2). Auto-created at repo
  root on every run, git-ignored (it stores absolute project paths). Top-level sections
  (`version:`, `repos:`, `local:`, `skills:`) are namespaced + versioned; the writers in
  `src/config.sh` splice one section at a time and preserve the rest. A v1 file is
  backed up to `config.yaml.v1.bak` and re-initialized.
- **`--sync` refreshes loaded repos** via `git submodule update --remote` (all repos, or
  `--repo author/name ...`). It touches only the library: moved submodule pointers are
  staged (never committed) and the repo's `lastUpdate` is bumped. Installed copies are
  not refreshed — the user runs `--update` afterwards.

## Version Control

- **Only touch version control when asked.** Do commits, merges, pushes, pull requests,
  branch deletions, etc. *only* when the user explicitly requests them. The user decides
  when to update the workspace or push to the origin. Otherwise, just do the job the user
  asked for and leave version-control actions alone.
- **Never commit straight to `main`.** Claude works on the `claude_space` branch; other
  agents use `{agent_name}_space` (e.g. Gemini → `gemini_space`). Branch off the latest
  `main` if the working branch doesn't exist yet.
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
- **Every `main` update gets a version tag.** Whenever the remote `main` is updated, create
  a matching annotated tag `v<major.minor.patch>` on that squashed commit and push it
  (`git tag -a vX.Y.Z <commit> -m ...` then `git push origin vX.Y.Z`), so `main` and its tag
  history always move forward together — there is always a version tag for each update. Also
  publish a GitHub release from the tag (`gh release create vX.Y.Z ...`) reusing the
  changelog as the notes. The tag version must match the changelog title's version.

## Interacting with the user

- When a request maps onto an existing operation, prefer running `main.sh` over ad-hoc
  commands, so behavior (confirmations, submodules, db updates, category defaults) stays
  consistent.
- `--load` only takes repo ROOT links. If the user gives a `/tree/...` subfolder link,
  convert it: the repo root becomes `--link` and the skill folder name becomes `--skill`
  (confirm with the user when the mapping isn't obvious).
- Report outcomes plainly: what was added/linked/removed and where. If something was
  skipped (e.g. missing `SKILL.md`, not a symlink), say so.

## Tool skill locations

| Tool             | Global (personal)                     | Project-scoped     |
|------------------|---------------------------------------|--------------------|
| Claude Desktop   | `~/.claude/skills/`                    | — (same as Code)   |
| Claude Code      | `~/.claude/skills/`                    | `.claude/skills/`  |
| Antigravity      | `~/.gemini/antigravity/skills/`        | `.agents/skills/`  |
| Antigravity IDE  | `~/.gemini/antigravity-ide/skills/`    | `.agents/skills/`  |
