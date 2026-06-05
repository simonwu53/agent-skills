# 533's Skills

A personal repository for **collecting** agent skills (from GitHub, local folders, or
zip archives) and **selectively installing** them into the tools you use — Claude Code /
Desktop, Antigravity, and Antigravity IDE — by symlinking only the skills you want
active at the moment.

The guiding philosophy: keep every skill you've ever found here, but only *install*
(symlink) the handful relevant to your current work, so agents see a focused set.

## Repository structure

```
.
├── skills/                  # Your skill library, grouped by category
│   ├── Academic/
│   │   └── pptx-poster/     # An individual skill (folder name = skill name)
│   │       ├── SKILL.md     # Core skill definition + prompt  (REQUIRED)
│   │       ├── scripts/     # Scripts the skill relies on     (optional)
│   │       ├── resources/   # Templates / assets              (optional)
│   │       └── examples/    # Usage examples                  (optional)
│   ├── Development/
│   │   └── ...
│   ├── macOS/
│   │   └── ...
│   └── Main/                # Default category when none is given
├── src/
│   ├── common.sh            # Shared helpers (logging, tool map, resolution)
│   ├── download.sh          # `--load` implementation
│   ├── install.sh           # `--install` implementation
│   └── remove.sh            # `--remove` implementation
├── test/                    # Validation / smoke tests
├── main.sh                  # Entry point for all operations
├── README.md
├── CLAUDE.md                # Instructions for Claude
└── GEMINI.md                # Instructions for Gemini / Antigravity
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

In **this repo** every skill lives one level under a category:
`skills/<Category>/<skill-name>/SKILL.md`. A directory is only treated as a valid skill
if it contains a `SKILL.md`.

## Requirements

Standard tools already present on macOS / in your shell: `bash` (3.2+), `git`, `curl`,
`unzip`, `rsync`. No installation needed. (`uv` + `.venv` are reserved for the rare case
a feature genuinely cannot be done in Bash; none currently do.)

## Usage

All operations run through `main.sh` from the repo root. Run `./main.sh --help` for the
quick reference.

### 1. Load (download / import) skills

```bash
# GitHub repo with skills/<Category>/<skill>/ layout — merge it in as-is
./main.sh --load --link https://github.com/owner/repo --merge

# GitHub repo with a flat skills/<skill>/ layout — drop all skills into one category
./main.sh --load --link https://github.com/owner/repo --cat Development

# GitHub link to a single skill folder
./main.sh --load --link https://github.com/owner/repo/tree/main/path/to/skill --cat Development

# Local skill folder
./main.sh --load -p ./path/to/skill --cat Development

# Zip archive containing a skill folder at its root
./main.sh --load -f ./skill.zip --cat Development
```

- The repo's skills folder is auto-detected by name: `skills`, `skill`, `SKILLS`, or `SKILL`.
- `--cat` / `-c` sets the target category; if omitted, skills go to **`Main`** (created if missing).
- GitHub downloads use a shallow **sparse-checkout**, so only the needed paths are fetched.
- Provide exactly **one** source (`--link`, `--path`, or `--file`).

### 2. Install skills (symlink into tools)

Install creates symlinks pointing at this repo, so editing a skill here updates it
everywhere it's installed.

```bash
# A single skill into ALL tools' global skill dirs
./main.sh --install --skill Academic/pptx-poster

# Into one tool's global dir (claude | antigravity | antigravity-ide)
./main.sh --install --skill Academic/pptx-poster --claude

# A whole category into one tool's global dir
./main.sh --install --skill Development --claude

# Into a project (per-tool project dir). Path optional → current directory.
./main.sh --install --skill Academic/pptx-poster --claude -p ./my-project

# Keep what's already installed instead of clearing the target first
./main.sh --install --skill Development --keep
```

- Target is `-s`/`--skill [Category]` (all skills in it) or `-s`/`--skill [Category]/[skill-name]` (one skill).
- No tool flag → all tools. Tool flags: `--claude`, `--antigravity`, `--antigravity-ide`.
- `-p` / `--path` switches to **project** scope. Omit the value to use the current dir.
- By default the target skills directory is **cleared first** (with a `y/n` confirmation),
  keeping only the skills you just installed. Pass `--keep` to add without clearing.
- The symlink is `…/skills/<skill-name>` → `skills/<Category>/<skill-name>` (the category
  is flattened away at the destination).

### 3. Remove skills (delete symlinks)

```bash
# Remove a skill from ALL global locations (asks to confirm)
./main.sh --remove --skill Academic/pptx-poster

# From one tool's global dir
./main.sh --remove --skill Academic/pptx-poster --claude

# A whole category from one tool's global dir
./main.sh --remove --skill Development --claude

# From a project (path optional → current dir)
./main.sh --remove --skill Academic/pptx-poster --claude -p ./my-project
```

Removal only deletes **symlinks** it finds (named after the skill). If a real directory
sits where the symlink would be, it is left untouched and reported. Removal always asks
for confirmation.

If the target is **pinned** (see below), removal warns you first, asks to confirm, and on
confirmation also deletes the matching pin from `config.yaml`.

### 4. Pin / Unpin skills (always-available)

Pinning records a skill in `config.yaml` **and** symlinks it immediately. After that,
every `--install` re-links your pinned skills *after* clearing the target — so they stay
available even when you install a fresh set without `--keep`.

```bash
# Pin a skill for one tool (records config + links it now)
./main.sh --pin --skill Academic/pptx-poster --claude

# Pin for all tools (omit the tool flag)
./main.sh --pin --skill Academic/pptx-poster

# Pin a whole category
./main.sh --pin --skill Development

# Pin into a project scope (path optional → current dir)
./main.sh --pin --skill Academic/pptx-poster --claude -p ./my-project

# Unpin — removes the config entry and the symlinks it created
./main.sh --unpin --skill Academic/pptx-poster --claude
```

- `--pin`/`--unpin` take the **same** flags as install/remove: `--skill`, the tool flags,
  and `-p`/`--path` for project scope. No tool flag → all tools; default scope is global.
- Pinning the same skill for another tool **merges** into the existing entry.

### 5. Unload skills (delete the source)

The inverse of `--load`: permanently delete a skill's (or a whole category's) **source**
from this repo's `skills/` library. Asks for confirmation first.

```bash
# Delete one skill's source
./main.sh --unload --skill Academic/pptx-poster

# Delete a whole category
./main.sh --unload --skill Development
```

- Empty category directories are removed afterward.
- Any pin entries covering what you deleted are stripped from `config.yaml`.
- Existing symlinks elsewhere that pointed at the deleted source will dangle (you're warned).

### Configuration (`config.yaml`)

State for pins (and future features) lives in a machine-local `config.yaml` at the repo
root. It is **auto-created on first run** and **git-ignored** (it stores absolute project
paths). The structure is namespaced and versioned so new features can add their own
top-level section without disturbing `pins`:

```yaml
version: 1

pins:
  - skill: Academic/pptx-poster
    tools: claude antigravity antigravity-ide
    scope: global
    path: ""
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
| `--load`            |       | op                | Download/import a skill                             |
| `--unload`          |       | op                | Delete a skill's/category's source from the repo    |
| `--install`         |       | op                | Symlink skill(s) into tools                         |
| `--remove`          |       | op                | Remove skill symlink(s)                             |
| `--pin`             |       | op                | Pin skill(s): link now + survive future installs    |
| `--unpin`           |       | op                | Remove a pin (config entry + its symlinks)          |
| `--link`            | `-l`  | load              | GitHub repo or skill-folder URL                    |
| `--path`            | `-p`  | load              | Local skill folder (source)                        |
| `--path`            | `-p`  | install / remove  | Project scope; value optional (current dir)        |
| `--file`            | `-f`  | load              | Zip archive                                        |
| `--cat`             | `-c`  | load              | Target category (default `Main`)                   |
| `--merge`           |       | load              | Merge a `skills/<Category>/<skill>` repo as-is     |
| `--claude` etc.     |       | install / remove  | Limit to a specific tool                           |
| `--keep`            |       | install           | Don't clear the target dir first                   |
| `--skill`           | `-s`  | install / remove  | Target selector `[Category]` or `[Category]/[skill]` |
