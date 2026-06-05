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

# resolve_skill_dirs_soft <category> <skill-or-empty>
# Like resolve_skill_dirs, but warns and returns non-zero instead of dying. Used
# when a missing skill (e.g. since --unloaded) must not abort the whole run.
resolve_skill_dirs_soft() {
  local category="$1" skill="$2"
  local base="$REPO_ROOT/skills/$category"
  [ -d "$base" ] || { warn "Category not found in repo: $category"; return 1; }

  if [ -n "$skill" ]; then
    local d="$base/$skill"
    is_skill_dir "$d" || { warn "Skill not found in repo: $category/$skill"; return 1; }
    printf '%s\n' "$d"
  else
    local found=0 d
    for d in "$base"/*/; do
      [ -d "$d" ] || continue
      d="${d%/}"
      if is_skill_dir "$d"; then printf '%s\n' "$d"; found=1; fi
    done
    [ "$found" -eq 1 ] || { warn "No valid skills found in category: $category"; return 1; }
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

# --- symlink helpers (shared by install / remove / pin) ----------------------

# link_skill <skill-dir> <dest-dir> — symlink dest/<name> -> <skill-dir>.
link_skill() {
  local skill="$1" dest="$2"
  local name; name="$(basename "$skill")"
  ln -sfn "$skill" "$dest/$name"
  info "Linked: $dest/$name -> $skill"
}

# unlink_skill <name> <dest-dir> — remove dest/<name> only if it is a symlink.
unlink_skill() {
  local name="$1" dest="$2"
  local entry="$dest/$name"
  if [ -L "$entry" ]; then
    rm -f "$entry"
    info "Removed: $entry"
  elif [ -e "$entry" ]; then
    warn "Not a symlink, leaving in place: $entry"
  else
    note "Not installed: $entry"
  fi
}

# build_dests <tools> <scope> <project-root> — print the deduped destination
# skills dirs (one per line) for a set of tools in the given scope.
build_dests() {
  local tools="$1" scope="$2" project_root="$3"
  local dests="" t d
  for t in $tools; do
    if [ "$scope" = "global" ]; then
      d="$(global_dir_for_tool "$t")" || { warn "Unknown tool: $t"; continue; }
    else
      d="$(project_dir_for_tool "$t" "$project_root")" || { warn "Unknown tool: $t"; continue; }
    fi
    _in_list "$dests" "$d" || dests="${dests:+$dests
}$d"
  done
  printf '%s\n' "$dests"
}

# --- machine-local configuration (config.yaml) -------------------------------
# shellcheck source=src/config.sh
. "$REPO_ROOT/src/config.sh"
