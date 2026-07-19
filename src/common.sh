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

# --- skill resolution (db-backed) --------------------------------------------

# A valid skill directory contains a SKILL.md file.
is_skill_dir() { [ -f "$1/SKILL.md" ]; }

# Library locations (relative to REPO_ROOT).
REPOSITORY_DIR="skills/repository"
LOCAL_DIR="skills/local"

# resolve_selector <selector>
# A selector is an exact skill name, or a category (→ every skill in it).
# Prints matching skill names, one per line. Dies when nothing matches.
resolve_selector() {
  local sel="$1"
  if config_skill_exists "$sel"; then
    config_skills_in_category "$sel" >/dev/null 2>&1 \
      && warn "'$sel' is both a skill and a category; using the skill."
    printf '%s\n' "$sel"
  else
    config_skills_in_category "$sel" \
      || die "No skill or category named '$sel' in the library (see --list)"
  fi
}

# resolve_selector_soft — like resolve_selector, but warns instead of dying.
resolve_selector_soft() {
  local sel="$1"
  if config_skill_exists "$sel"; then
    printf '%s\n' "$sel"
  else
    config_skills_in_category "$sel" \
      || { warn "No skill or category named '$sel' in the library"; return 1; }
  fi
}

# skill_dir_checked <name> — resolve the skill's source dir and verify it holds
# a SKILL.md. Hints at submodule init when the checkout is missing.
skill_dir_checked() {
  local name="$1" d
  d="$(config_skill_dir "$name")" || die "Skill '$name' has no resolvable source in config.yaml"
  if [ ! -d "$d" ]; then
    die "Source folder missing for '$name': $d
Is the submodule initialized? Try: git submodule update --init"
  fi
  is_skill_dir "$d" || die "Not a valid skill (no SKILL.md): $d"
  printf '%s\n' "$d"
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

# link_skill <skill-dir> <dest-dir> <name> [mode] — install skill into dest as
# <name> (the db skill name; the source dir's basename may differ, e.g. for a
# repo whose root is the skill). mode "copy" (default) duplicates the folder so
# tools that don't follow symlinks (e.g. Claude Desktop) can see it; mode
# "symlink" creates a soft link instead.
link_skill() {
  local skill="$1" dest="$2" name="$3" mode="${4:-copy}"
  local entry="$dest/$name"
  if [ "$mode" = "symlink" ]; then
    ln -sfn "$skill" "$entry"
    info "Linked: $entry -> $skill"
  else
    rm -rf "$entry"
    cp -R "$skill" "$entry"
    # A repo-root skill's copy would carry the submodule's .git pointer.
    rm -rf "$entry/.git"
    info "Copied: $entry"
  fi
}

# unlink_skill <name> <dest-dir> — remove dest/<name> if it is a managed skill:
# a symlink we created, or a copied skill directory (identified by its SKILL.md).
# Anything else (a real dir that isn't a skill) is left untouched and reported.
unlink_skill() {
  local name="$1" dest="$2"
  local entry="$dest/$name"
  if [ -L "$entry" ]; then
    rm -f "$entry"
    info "Removed: $entry"
  elif [ -d "$entry" ] && is_skill_dir "$entry"; then
    rm -rf "$entry"
    info "Removed: $entry"
  elif [ -e "$entry" ]; then
    warn "Not a managed skill, leaving in place: $entry"
  else
    note "Not installed: $entry"
  fi
}

# record_install <name> <scope> <project-root> <tools> <dest>
# Update the skill's install state in the db after a successful install.
# Shared by install and pin.
record_install() {
  local name="$1" scope="$2" project_root="$3" tools="$4" dest="$5" t
  if [ "$scope" = "global" ]; then
    for t in $tools; do
      [ "$(global_dir_for_tool "$t")" = "$dest" ] && config_skill_add_agent "$name" "$t"
    done
  else
    config_skill_add_project "$name" "$project_root"
  fi
  return 0
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
