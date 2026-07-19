# 533's Skills

A personal repository for **collecting** agent skills (from GitHub, local folders, or
zip archives) and **selectively installing** them into the tools you use — Claude Code /
Desktop, Antigravity, and Antigravity IDE — by copying only the skills you want
active at the moment.

The guiding philosophy: keep every skill you've ever found here, but only *install*
the handful relevant to your current work, so agents see a focused set.

The library keeps **whole source repos** (as git submodules), so skills stay linked to
where they came from — updating a skill later is just updating its repo dependency.
`config.yaml` is the database that records what's loaded, its category, pin status,
and where it's installed.

## Repository structure

```
.
├── skills/
│   ├── repository/          # Source repos, added as git submodules
│   │   └── <author>-<repo>/ #   e.g. emilkowalski-skills/ (skills stay inside)
│   └── local/               # Skills loaded from local folders / zip archives
│       └── <skill-name>/
├── src/
│   ├── common.sh            # Shared helpers (logging, tool map, resolution)
│   ├── config.sh            # config.yaml (library db) read/write layer
│   ├── download.sh          # `--load` / `--unload` implementation
│   ├── install.sh           # `--install` / `--update` implementation
│   ├── remove.sh            # `--remove` implementation
│   ├── pin.sh               # `--pin` / `--unpin` implementation
│   └── list.sh              # `--list` implementation
├── test/                    # Validation / smoke tests
├── main.sh                  # Entry point for all operations
├── config.yaml              # Library database (machine-local, git-ignored)
├── README.md
└── CLAUDE.md                # Instructions for Claude
```

### Skill folder layout

Each skill is one directory whose name is the skill's name. The only required file is
`SKILL.md`. The layout follows the
[Agent Skills specification](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview):

```
<skill-name>/
├── SKILL.md      # REQUIRED — YAML frontmatter (name, description) + instructions
├── scripts/      # optional — executable helpers the skill calls
├── resources/    # optional — templates, data, or other assets
└── examples/     # optional — example inputs/outputs showing usage
```

A directory is only treated as a valid skill if it contains a `SKILL.md`. Skills are
**not** copied out of their source repos — `config.yaml` records each skill's repo and
subpath, and install resolves the folder from there.

## Requirements

Standard tools already present on macOS / in your shell: `bash` (3.2+), `git`, `curl`,
`unzip`, `rsync`. No installation needed. (`uv` + `.venv` are reserved for the rare case
a feature genuinely cannot be done in Bash; none currently do.)

## Usage

All operations run through `main.sh` from the repo root. Run `./main.sh --help` for the
quick reference.

### 1. Load skills into the library

`--load --link` takes a GitHub **repo root** link (subfolder `/tree/...` links are not
supported). The repo is added as a git submodule under `skills/repository/<author>-<repo>/`
and the selected skills are registered in `config.yaml`.

```bash
# Auto mode: SKILL.md at the repo root → the repo itself is one skill;
# otherwise every subfolder of skills/ is a skill (batch adds ask y/n first)
./main.sh --load --link https://github.com/owner/repo
./main.sh --load --link https://github.com/owner/repo --cat Development

# Select specific skills inside the repo's skills/ folder
./main.sh --load --link https://github.com/owner/repo --skill my-skill other-skill

# Repo nests categories (skills/Coding/create-figure/) — category is inferred
# from the path ("Coding" here) unless --cat overrides it
./main.sh --load --link https://github.com/owner/repo --skill Coding/create-figure

# Local skill folder / zip archive → stored under skills/local/<name>/
./main.sh --load -p ./path/to/skill --cat Development
./main.sh --load -f ./skill.zip --cat Development
```

- The repo's skills folder is auto-detected by name: `skills`, `skill`, `SKILLS`, or `SKILL`.
- `--cat` / `-c` sets the category recorded for the loaded skill(s); default **`Main`**.
- **Skill names are unique** — one name, one workflow. Loading a skill whose name already
  exists (from a different source) asks whether to **replace** the old one (double-confirmed;
  the old source is cleaned up like `--unload`) or keep it (the new skill is skipped).
- Loading more skills from an already-loaded repo reuses the existing submodule.
- Provide exactly **one** source (`--link`, `--path`, or `--file`).

To update loaded repos to their latest upstream state, use git's submodule machinery
(e.g. `git submodule update --remote skills/repository/<author>-<repo>`); a dedicated
`--sync` operation is planned.

### 2. Install skills (copy into tools)

Install **copies** each skill into the tool's skills directory by default, so tools that
don't follow symlinks (notably Claude Desktop) can still see them. Pass `--symlink` to
create soft links pointing at the library instead (so submodule updates propagate).

```bash
# A single skill into ALL tools' global skill dirs
./main.sh --install --skill my-skill

# Into one tool's global dir (claude | antigravity | antigravity-ide)
./main.sh --install --skill my-skill --claude

# Several skills at once
./main.sh --install --skill my-skill other-skill --claude

# A whole category into one tool's global dir
./main.sh --install --skill Development --claude

# Into a project (per-tool project dir). Path optional → current directory.
./main.sh --install --skill my-skill --claude -p ./my-project

# Keep what's already installed instead of clearing the target first
./main.sh --install --skill Development --keep

# Symlink instead of copying
./main.sh --install --skill Development --symlink

# Re-install (overwrite) a skill that's already there, no prompt
./main.sh --update --skill my-skill --claude
```

- Target is `-s`/`--skill` followed by **skill name(s) and/or category name(s)** — a
  category selector installs every skill in it. (If a name is both a skill and a
  category, the skill wins and you're warned.)
- No tool flag → all tools. Tool flags: `--claude`, `--antigravity`, `--antigravity-ide`.
- `-p` / `--path` switches to **project** scope. Omit the value to use the current dir.
- By default the target skills directory is **cleared first** (with a `y/n` confirmation),
  keeping only the skills you just installed (plus pinned skills, see below). Pass
  `--keep` to add without clearing.
- The skill lands at `…/skills/<skill-name>`. Each install/remove also updates the
  skill's `agents` / `projects` install state in `config.yaml`.
- When a skill you're installing **already exists** in the target, `--install` warns and
  asks `y/n` before overwriting it (declining skips just that skill). Use **`--update`** to
  overwrite the named skill(s) without prompting — it only touches those skills (it implies
  `--keep`, so the rest of the target dir is left alone).

### 3. List skills

```bash
# The library, grouped by category (read from config.yaml)
./main.sh --list

# Skills installed for a tool (global scope)
./main.sh --list --claude

# Skills installed for a tool in a project scope (path optional → current dir)
./main.sh --list --claude -p ./my-project
```

- With **no** tool flag or `-p`, `--list` shows the library from `config.yaml`: each
  skill with its source (`author/repo` or `local`) and a `(pinned)` marker.
- With a tool flag (and/or `-p`), it shows what's installed in that tool's skills dir,
  marking each entry as a `(copy)` or `(symlink)`.

### 4. Remove skills

```bash
# Remove a skill from ALL global locations (asks to confirm)
./main.sh --remove --skill my-skill

# Remove several at once
./main.sh --remove --skill my-skill foo --claude

# Remove EVERY installed skill for a tool (omit --skill)
./main.sh --remove --claude

# From a project (path optional → current dir)
./main.sh --remove --skill my-skill --claude -p ./my-project
```

- Target is `-s`/`--skill <skill-name>`; pass multiple names to remove several at once.
- **Omit `--skill` entirely to remove all installed skills** for the targeted tool(s).
- Removal deletes the installed skill whether it's a **copy** (a directory holding
  `SKILL.md`) or a **symlink**. A directory that isn't a managed skill is left untouched
  and reported. Removal always asks for confirmation, and updates the install state in
  `config.yaml`.

If the target is **pinned** (see below), removal warns you first and, on confirmation,
also unpins it — otherwise the next install-clear would just bring it back.

### 5. Pin / Unpin skills (always-available)

Pinning sets `pinned: true` on the skill in `config.yaml` **and** installs it
immediately. After that, every install-time clear re-installs all pinned skills into the
cleared directory — so pins survive every `--install` without `--keep`. (Re-installed
pins follow that install run's copy/symlink mode.)

```bash
# Pin a skill and install it now for one tool
./main.sh --pin --skill my-skill --claude

# Pin for all tools (omit the tool flag)
./main.sh --pin --skill my-skill

# Pin a whole category
./main.sh --pin --skill Development

# Pin into a project scope (path optional → current dir)
./main.sh --pin --skill my-skill --claude -p ./my-project

# Unpin — clears the flag only; installed copies stay (use --remove to uninstall)
./main.sh --unpin --skill my-skill
```

- `--pin`/`--unpin` take the same selectors as install: skill names and/or categories.
- The pin itself is a plain flag (no per-tool records); the tool flags and `-p` on
  `--pin` only choose where the immediate install goes.

### 6. Unload skills (remove from the library)

The inverse of `--load`: drop skill(s) from the db and clean up their sources. Asks for
confirmation first.

```bash
# Unload one skill
./main.sh --unload --skill my-skill

# Unload a whole category
./main.sh --unload --skill Development
```

- Local skills (`skills/local/<name>/`) have their source folder deleted.
- A repo submodule is removed (deinit + `git rm`) once its **last** skill is unloaded —
  with its own confirmation.
- Existing symlinks elsewhere that pointed at the deleted source will dangle (you're warned).

### Configuration (`config.yaml`)

`config.yaml` at the repo root is the library database. It is **auto-created on first
run** and **git-ignored** (machine-local; it stores absolute project paths in install
state). Top-level sections are namespaced and versioned so future features can add
their own:

```yaml
version: 2

repos:
  - name: skills                      # repo name (from the URL)
    author: emilkowalski              # repo owner (from the URL)
    url: https://github.com/emilkowalski/skills
    path: skills/repository/emilkowalski-skills
    lastUpdate: 2026-07-19 14:30:00
    dateAdded: 2026-07-19 14:30:00

local:
  - name: my-skill
    path: skills/local/my-skill
    source: /Users/me/Downloads/my-skill.zip   # original source, informational
    dateAdded: 2026-07-19 14:30:00

skills:
  - name: apple-design                # unique; also the installed folder name
    repo: emilkowalski/skills         # <author>/<repo> slug, or "local"
    subpath: skills/apple-design      # "" = the repo root is the skill folder
    category: Design
    pinned: false
    agents: claude antigravity        # global-scope installs
    projects:                         # project-scope installs
      - /Users/me/some/project
```

## Tool skill locations

| Tool             | Global (personal)                     | Project-scoped     |
|------------------|---------------------------------------|--------------------|
| Claude Desktop   | `~/.claude/skills/`                    | — (same as Code)   |
| Claude Code      | `~/.claude/skills/`                    | `.claude/skills/`  |
| Antigravity      | `~/.gemini/antigravity/skills/`        | `.agents/skills/`  |
| Antigravity IDE  | `~/.gemini/antigravity-ide/skills/`    | `.agents/skills/`  |

## Flag reference

| Flag                | Alias | Applies to        | Meaning                                            |
|---------------------|-------|-------------------|----------------------------------------------------|
| `--load`            |       | op                | Load a repo (submodule) / local source; register skills |
| `--unload`          |       | op                | Remove skill(s) from the library + clean up sources |
| `--install`         |       | op                | Install skill(s) into tools (copy by default)       |
| `--update`          |       | op                | Install, overwriting existing skill(s) without prompt|
| `--remove`          |       | op                | Remove installed skill(s)                           |
| `--list`            |       | op                | List the library, or installed skills (with a tool flag)|
| `--pin`             |       | op                | Pin skill(s): install now + survive install-clears  |
| `--unpin`           |       | op                | Clear the pin flag (copies stay installed)          |
| `--link`            | `-l`  | load              | GitHub repo ROOT link                               |
| `--path`            | `-p`  | load              | Local skill folder (source)                        |
| `--path`            | `-p`  | install / remove / list / pin | Project scope; value optional (current dir) |
| `--file`            | `-f`  | load              | Zip archive                                        |
| `--cat`             | `-c`  | load              | Category for the loaded skill(s) (default `Main`)  |
| `--skill`           | `-s`  | load              | Skill(s) inside the repo: `name` or `Cat/name`     |
| `--claude` etc.     |       | install / remove / list / pin | Limit to a specific tool                 |
| `--keep`            |       | install           | Don't clear the target dir first                   |
| `--symlink`         |       | install           | Symlink instead of copying (default: copy)         |
| `--skill`           | `-s`  | install / remove / pin / unload | Skill name(s) and/or category name(s) |
