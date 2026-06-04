#!/usr/bin/env bash
# common.sh — shared helpers for the skills manager.
# Sourced by main.sh and the op scripts. Bash 3.2 / Zsh compatible.

# --- logging -----------------------------------------------------------------

if [ -t 1 ]; then
  _C_RED=$'\033[31m'; _C_YEL=$'\033[33m'; _C_GRN=$'\033[32m'
  _C_DIM=$'\033[2m'; _C_RST=$'\033[0m'
else
  _C_RED=""; _C_YEL=""; _C_GRN=""; _C_DIM=""; _C_RST=""
fi

info() { printf '%s\n' "${_C_GRN}==>${_C_RST} $*"; }
warn() { printf '%s\n' "${_C_YEL}warn:${_C_RST} $*" >&2; }
err()  { printf '%s\n' "${_C_RED}error:${_C_RST} $*" >&2; }
die()  { err "$*"; exit 1; }
note() { printf '%s\n' "${_C_DIM}$*${_C_RST}"; }

# --- temp dir tracking -------------------------------------------------------
# make_tmp prints a fresh temp dir and registers it for cleanup at process exit.
# (A single EXIT trap avoids the non-local-RETURN-trap pitfall under `set -u`.)
_TMPDIRS=""
make_tmp() {
  local d; d="$(mktemp -d)"
  _TMPDIRS="${_TMPDIRS} $d"
  printf '%s\n' "$d"
}
_cleanup_tmp() {
  local d
  for d in ${_TMPDIRS:-}; do rm -rf "$d"; done
}
trap _cleanup_tmp EXIT

# confirm "question" -> returns 0 on yes, 1 on no. Defaults to no on empty.
confirm() {
  local prompt="$1" reply
  printf '%s [y/N] ' "$prompt" >&2
  read -r reply
  case "$reply" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# --- tool location map -------------------------------------------------------

ALL_TOOLS="claude antigravity antigravity-ide"

# global_dir_for_tool <tool> -> prints global skills dir for that tool
global_dir_for_tool() {
  case "$1" in
    claude)          printf '%s\n' "$HOME/.claude/skills" ;;
    antigravity)     printf '%s\n' "$HOME/.gemini/antigravity/skills" ;;
    antigravity-ide) printf '%s\n' "$HOME/.gemini/antigravity-ide/skills" ;;
    *) return 1 ;;
  esac
}

# project_dir_for_tool <tool> <project-root> -> prints project skills dir
project_dir_for_tool() {
  case "$1" in
    claude)                      printf '%s\n' "$2/.claude/skills" ;;
    antigravity|antigravity-ide) printf '%s\n' "$2/.agents/skills" ;;
    *) return 1 ;;
  esac
}

# --- skill resolution --------------------------------------------------------

# A valid skill directory contains a SKILL.md file.
is_skill_dir() { [ -f "$1/SKILL.md" ]; }

# resolve_skill_dirs <category> <skill-or-empty>
# Prints absolute skill directory paths, one per line, from the repo's skills/.
# If <skill> is empty, lists every skill in the category.
resolve_skill_dirs() {
  local category="$1" skill="$2"
  local base="$REPO_ROOT/skills/$category"
  [ -d "$base" ] || die "Category not found in repo: $category"

  if [ -n "$skill" ]; then
    local d="$base/$skill"
    [ -d "$d" ] || die "Skill not found in repo: $category/$skill"
    is_skill_dir "$d" || die "Not a valid skill (no SKILL.md): $category/$skill"
    printf '%s\n' "$d"
  else
    local found=0 d
    for d in "$base"/*/; do
      [ -d "$d" ] || continue
      d="${d%/}"
      if is_skill_dir "$d"; then printf '%s\n' "$d"; found=1; fi
    done
    [ "$found" -eq 1 ] || die "No valid skills found in category: $category"
  fi
}

# split_target <selector>  e.g. "Academic/pptx-poster" or "Academic"
# Sets TARGET_CATEGORY and TARGET_SKILL (skill may be empty).
split_target() {
  local sel="$1"
  case "$sel" in
    */*) TARGET_CATEGORY="${sel%%/*}"; TARGET_SKILL="${sel#*/}" ;;
    *)   TARGET_CATEGORY="$sel";        TARGET_SKILL="" ;;
  esac
  [ -n "$TARGET_CATEGORY" ] || die "Empty target selector"
}

# dedupe_append <listvar-name> <value>  — append value if not already present.
# Uses a newline-delimited string held in the named variable.
_in_list() {
  # _in_list "$list" "$value"
  case "
$1
" in
    *"
$2
"*) return 0 ;;
    *) return 1 ;;
  esac
}
