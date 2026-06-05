#!/usr/bin/env bash
# main.sh — entry point for the personal skills manager.
#
#   ./main.sh --load    ...   download/import skills into this repo
#   ./main.sh --install ...   symlink skills into agent tool directories
#   ./main.sh --remove  ...   remove those symlinks
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

Operations:
  --load      Download/import a skill into this repo's skills/ folder
  --unload    Delete a skill's (or category's) source from this repo
  --install   Install skill(s) into agent tool skill directories (copy by default)
  --update    Like --install but overwrite existing skills without prompting
  --remove    Remove installed skill(s) from agent tool skill directories
  --list      List skills in this repo, or installed in a tool (with a tool flag)
  --pin       Pin skill(s): install now + keep them through future installs
  --unpin     Remove a pin (config + the skills it installed)

Load options:
  -l, --link <url>    GitHub repo URL or skill-folder URL
  -p, --path <dir>    Local skill folder to copy in
  -f, --file <zip>    Zip archive containing a skill folder
  -c, --cat  <name>   Target category (default: Main)
      --merge         Repo has skills/<category>/<skill> layout; merge as-is

Install target & options:
  -s, --skill [Category]              Install every skill in a category
  -s, --skill [Category]/[skill-name] Install a single skill
  -s, --skill A B ...                 Multiple selectors at once
  --claude | --antigravity | --antigravity-ide
                              Limit to one tool (default: all)
  -p, --path [dir]            Project scope (omit value for current dir)
      --keep                  Don't clear the target dir first
      --symlink               Symlink instead of copying (default: copy)

Remove target & options:
  -s, --skill [skill-name] ...        Remove the named installed skill(s)
                              Omit --skill to remove ALL installed skills
  --claude | --antigravity | --antigravity-ide
                              Limit to one tool (default: all)
  -p, --path [dir]            Project scope (omit value for current dir)

List options:
  (no flag)                   List every skill in this repo, grouped by category
  --claude | --antigravity | --antigravity-ide
                              List skills installed for that tool instead
  -p, --path [dir]            Project scope (omit value for current dir)

Examples:
  main.sh --load --link https://github.com/owner/repo --merge
  main.sh --load --link https://github.com/owner/repo --cat Development
  main.sh --load --link https://github.com/owner/repo/tree/main/path/to/skill --cat Development
  main.sh --load -p ./my-skill --cat Development
  main.sh --load -f ./my-skill.zip --cat Development

  main.sh --install --skill Academic/pptx-poster
  main.sh --install --skill Academic/pptx-poster --claude
  main.sh --install --skill Development --claude
  main.sh --install --skill Academic/pptx-poster Development/foo --claude
  main.sh --install --skill Academic/pptx-poster --claude -p ./my-project
  main.sh --install --skill Development --keep
  main.sh --install --skill Development --symlink

  main.sh --update --skill Academic/pptx-poster --claude

  main.sh --list
  main.sh --list --claude
  main.sh --list --claude -p ./my-project

  main.sh --remove --skill pptx-poster
  main.sh --remove --skill pptx-poster foo --claude
  main.sh --remove --claude                     # remove ALL skills for claude
  main.sh --remove --skill pptx-poster --claude -p ./my-project

  main.sh --pin --skill Academic/pptx-poster --claude
  main.sh --pin --skill Development            # pin a whole category, all tools
  main.sh --unpin --skill Academic/pptx-poster --claude

  main.sh --unload --skill Academic/pptx-poster
  main.sh --unload --skill Development          # delete the whole category
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
