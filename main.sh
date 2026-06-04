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
  --install   Symlink skill(s) into agent tool skill directories
  --remove    Remove skill symlink(s) from agent tool skill directories

Load options:
  -l, --link <url>    GitHub repo URL or skill-folder URL
  -p, --path <dir>    Local skill folder to copy in
  -f, --file <zip>    Zip archive containing a skill folder
  -c, --cat  <name>   Target category (default: Main)
      --merge         Repo has skills/<category>/<skill> layout; merge as-is

Install / Remove target & options:
  --[Category]                Act on every skill in a category
  --[Category]/[skill-name]   Act on a single skill
  --claude | --antigravity | --antigravity-ide
                              Limit to one tool (default: all)
  -p, --path [dir]            Project scope (omit value for current dir)
      --keep                  (install) Don't clear the target dir first

Examples:
  main.sh --load --link https://github.com/owner/repo --merge
  main.sh --load --link https://github.com/owner/repo --cat Development
  main.sh --load --link https://github.com/owner/repo/tree/main/path/to/skill --cat Development
  main.sh --load -p ./my-skill --cat Development
  main.sh --load -f ./my-skill.zip --cat Development

  main.sh --install --Academic/pptx-poster
  main.sh --install --Academic/pptx-poster --claude
  main.sh --install --Development --claude
  main.sh --install --Academic/pptx-poster --claude -p ./my-project
  main.sh --install --Development --keep

  main.sh --remove --Academic/pptx-poster
  main.sh --remove --Academic/pptx-poster --claude
  main.sh --remove --Development --claude
  main.sh --remove --Academic/pptx-poster --claude -p ./my-project
EOF
}

main() {
  if [ $# -eq 0 ]; then usage; exit 1; fi

  local op=""
  local a
  for a in "$@"; do
    case "$a" in
      --load)    op="load" ;;
      --install) op="install" ;;
      --remove)  op="remove" ;;
      -h|--help) usage; exit 0 ;;
    esac
  done

  case "$op" in
    load)    . "$REPO_ROOT/src/download.sh"; download_main "$@" ;;
    install) . "$REPO_ROOT/src/install.sh";  install_main "$@" ;;
    remove)  . "$REPO_ROOT/src/remove.sh";   remove_main "$@" ;;
    *) err "No operation given (--load | --install | --remove)"; usage; exit 1 ;;
  esac
}

main "$@"
