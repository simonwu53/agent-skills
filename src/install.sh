#!/usr/bin/env bash
# install.sh — implements `main.sh --install ...`
# Creates symlinks from a tool's skills directory to skills in this repo.

# clear_dir <dir> — remove every entry inside <dir> after confirmation.
clear_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  # Anything to clear?
  if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
    return 0
  fi
  if confirm "Clear all existing skills in '$dir'?"; then
    find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    note "Cleared: $dir"
  else
    warn "Keeping existing contents of: $dir"
  fi
}

# link_skill <skill-dir> <dest-dir> — symlink dest/<name> -> <skill-dir>.
link_skill() {
  local skill="$1" dest="$2"
  local name; name="$(basename "$skill")"
  ln -sfn "$skill" "$dest/$name"
  info "Linked: $dest/$name -> $skill"
}

install_main() {
  local target="" scope="global" project_root="" keep=0
  local tools=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --install) ;;
      --claude)          tools="$tools claude" ;;
      --antigravity)     tools="$tools antigravity" ;;
      --antigravity-ide) tools="$tools antigravity-ide" ;;
      --keep) keep=1 ;;
      -p|--path)
        scope="project"
        if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
          project_root="$2"; shift
        else
          project_root="."
        fi
        ;;
      --*) target="${1#--}" ;;
      *) warn "Ignoring unexpected argument: $1" ;;
    esac
    shift
  done

  [ -n "$target" ] || die "No target. Use --[Category] or --[Category]/[skill-name]"

  # Default to all tools when none specified.
  [ -n "$tools" ] || tools="$ALL_TOOLS"

  # Resolve project root to an absolute path.
  if [ "$scope" = "project" ]; then
    [ -d "$project_root" ] || die "Project path is not a directory: $project_root"
    project_root="$(cd "$project_root" && pwd)"
  fi

  split_target "$target"
  local skill_dirs; skill_dirs="$(resolve_skill_dirs "$TARGET_CATEGORY" "$TARGET_SKILL")"

  # Build a deduped list of destination directories.
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
  [ -n "$dests" ] || die "No valid destinations resolved"

  info "Installing '$target' ($scope) to:"
  local OLDIFS="$IFS"; IFS='
'
  for d in $dests; do note "  $d"; done

  # Per destination: optionally clear, then symlink each skill. Use newline-IFS
  # for-loops (not piped while-read) so confirm prompts keep reading the tty.
  for d in $dests; do
    mkdir -p "$d"
    [ "$keep" -eq 1 ] || clear_dir "$d"
    local s
    for s in $skill_dirs; do
      link_skill "$s" "$d"
    done
  done
  IFS="$OLDIFS"

  info "Done."
}
