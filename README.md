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
./main.sh --install --Academic/pptx-poster

# Into one tool's global dir (claude | antigravity | antigravity-ide)
./main.sh --install --Academic/pptx-poster --claude

# A whole category into one tool's global dir
./main.sh --install --Development --claude

# Into a project (per-tool project dir). Path optional → current directory.
./main.sh --install --Academic/pptx-poster --claude -p ./my-project

# Keep what's already installed instead of clearing the target first
./main.sh --install --Development --keep
```

- Target is `--[Category]` (all skills in it) or `--[Category]/[skill-name]` (one skill).
- No tool flag → all tools. Tool flags: `--claude`, `--antigravity`, `--antigravity-ide`.
- `-p` / `--path` switches to **project** scope. Omit the value to use the current dir.
- By default the target skills directory is **cleared first** (with a `y/n` confirmation),
  keeping only the skills you just installed. Pass `--keep` to add without clearing.
- The symlink is `…/skills/<skill-name>` → `skills/<Category>/<skill-name>` (the category
  is flattened away at the destination).

### 3. Remove skills (delete symlinks)

```bash
# Remove a skill from ALL global locations (asks to confirm)
./main.sh --remove --Academic/pptx-poster

# From one tool's global dir
./main.sh --remove --Academic/pptx-poster --claude

# A whole category from one tool's global dir
./main.sh --remove --Development --claude

# From a project (path optional → current dir)
./main.sh --remove --Academic/pptx-poster --claude -p ./my-project
```

Removal only deletes **symlinks** it finds (named after the skill). If a real directory
sits where the symlink would be, it is left untouched and reported. Removal always asks
for confirmation.

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
| `--install`         |       | op                | Symlink skill(s) into tools                         |
| `--remove`          |       | op                | Remove skill symlink(s)                             |
| `--link`            | `-l`  | load              | GitHub repo or skill-folder URL                    |
| `--path`            | `-p`  | load              | Local skill folder (source)                        |
| `--path`            | `-p`  | install / remove  | Project scope; value optional (current dir)        |
| `--file`            | `-f`  | load              | Zip archive                                        |
| `--cat`             | `-c`  | load              | Target category (default `Main`)                   |
| `--merge`           |       | load              | Merge a `skills/<Category>/<skill>` repo as-is     |
| `--claude` etc.     |       | install / remove  | Limit to a specific tool                           |
| `--keep`            |       | install           | Don't clear the target dir first                   |
| `--[Category][/skill]` |    | install / remove  | Target selector                                    |
