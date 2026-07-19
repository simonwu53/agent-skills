#!/usr/bin/env bash
# main.sh — entry point for the personal skills manager.
#
#   ./main.sh --load    ...   load a source repo/folder into the library
#   ./main.sh --install ...   install skills into agent tool directories
#   ./main.sh --remove  ...   remove installed skills
#
# See README.md for full usage.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export REPO_ROOT

# shellcheck source=src/common.sh
. "$REPO_ROOT/src/common.sh"

usage() {
  cat <<'EOF'
Usage: main.sh <operation> [target] [options]

The library keeps whole source repos as git submodules under skills/repository/
(local sources under skills/local/); config.yaml records every loaded repo and
skill (category, pin flag, install state).

Operations:
  --load      Load a repo (submodule) or local source and register its skills
  --unload    Remove skill(s) from the library (db entry + source cleanup)
  --install   Install skill(s) into agent tool skill directories (copy by default)
  --update    Like --install but overwrite existing skills without prompting
  --remove    Remove installed skill(s) from agent tool skill directories
  --list      List the library, or skills installed in a tool (with a tool flag)
  --pin       Pin skill(s): install now + re-install after any install-clear
  --unpin     Clear the pin flag (installed copies stay; use --remove to uninstall)

Load options:
  -l, --link <url>       GitHub repo ROOT link (subfolder /tree/ links are not
                         supported). Without --skill, auto mode applies:
                         SKILL.md at repo root → the repo is one skill; else
                         every subfolder of skills/ is a skill (not a category)
  -s, --skill <sel> ...  Select skills inside the repo's skills folder:
                         "name" → skills/name; "Cat/name" → skills/Cat/name
                         (category inferred from the path unless --cat is given)
  -p, --path <dir>       Local skill folder to store under skills/local/
  -f, --file <zip>       Zip archive to store under skills/local/
  -c, --cat  <name>      Category for the loaded skill(s) (default: Main)

Install target & options:
  -s, --skill <name> ...      Skill name(s) and/or category name(s)
  --claude | --antigravity | --antigravity-ide
                              Limit to one tool (default: all)
  -p, --path [dir]            Project scope (omit value for current dir)
      --keep                  Don't clear the target dir first
      --symlink               Symlink instead of copying (default: copy)

Remove target & options:
  -s, --skill <name> ...      Remove the named installed skill(s)
                              Omit --skill to remove ALL installed skills
  --claude | --antigravity | --antigravity-ide
                              Limit to one tool (default: all)
  -p, --path [dir]            Project scope (omit value for current dir)

List options:
  (no flag)                   List the library, grouped by category
  --claude | --antigravity | --antigravity-ide
                              List skills installed for that tool instead
  -p, --path [dir]            Project scope (omit value for current dir)

Examples:
  main.sh --load --link https://github.com/owner/repo                # auto mode
  main.sh --load --link https://github.com/owner/repo --cat Development
  main.sh --load --link https://github.com/owner/repo --skill my-skill
  main.sh --load --link https://github.com/owner/repo --skill Coding/create-figure
  main.sh --load -p ./my-skill --cat Development
  main.sh --load -f ./my-skill.zip --cat Development

  main.sh --install --skill my-skill
  main.sh --install --skill my-skill --claude
  main.sh --install --skill Development --claude     # whole category
  main.sh --install --skill my-skill other-skill --claude
  main.sh --install --skill my-skill --claude -p ./my-project
  main.sh --install --skill Development --keep
  main.sh --install --skill Development --symlink

  main.sh --update --skill my-skill --claude

  main.sh --list
  main.sh --list --claude
  main.sh --list --claude -p ./my-project

  main.sh --remove --skill my-skill
  main.sh --remove --skill my-skill foo --claude
  main.sh --remove --claude                     # remove ALL skills for claude
  main.sh --remove --skill my-skill --claude -p ./my-project

  main.sh --pin --skill my-skill --claude
  main.sh --pin --skill Development             # pin a whole category
  main.sh --unpin --skill my-skill

  main.sh --unload --skill my-skill
  main.sh --unload --skill Development          # unload the whole category
EOF
}

main() {
  if [ $# -eq 0 ]; then usage; exit 1; fi

  # Ensure machine-local config.yaml exists (and is git-ignored).
  init_config

  local op=""
  local a
  for a in "$@"; do
    case "$a" in
      --load)    op="load" ;;
      --unload)  op="unload" ;;
      --install) op="install" ;;
      --update)  op="install" ;;   # alias: install, overwriting without prompts
      --remove)  op="remove" ;;
      --list)    op="list" ;;
      --pin)     op="pin" ;;
      --unpin)   op="unpin" ;;
      -h|--help) usage; exit 0 ;;
    esac
  done

  case "$op" in
    load)    . "$REPO_ROOT/src/download.sh"; download_main "$@" ;;
    unload)  . "$REPO_ROOT/src/download.sh"; unload_main "$@" ;;
    install) . "$REPO_ROOT/src/install.sh";  install_main "$@" ;;
    remove)  . "$REPO_ROOT/src/remove.sh";   remove_main "$@" ;;
    list)    . "$REPO_ROOT/src/list.sh";     list_main "$@" ;;
    pin)     . "$REPO_ROOT/src/pin.sh";      pin_main "$@" ;;
    unpin)   . "$REPO_ROOT/src/pin.sh";      unpin_main "$@" ;;
    *) err "No operation given (--load | --unload | --install | --update | --remove | --list | --pin | --unpin)"; usage; exit 1 ;;
  esac
}

main "$@"
