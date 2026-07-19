#!/usr/bin/env bash
# install.sh — implements `main.sh --install ...` (and its --update alias)
# Copies (default) or symlinks library skills into agent tool skill directories,
# resolving each skill's source folder through config.yaml (repo + subpath).

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

# reinstall_pinned_into <dest> <scope> <project-root> <tools> [mode]
# After a clear, re-install every pinned skill so pins survive any clear.
reinstall_pinned_into() {
  local dest="$1" scope="$2" project_root="$3" tools="$4" mode="${5:-copy}"
  local OLDIFS="$IFS" nm d
  IFS='
'
  for nm in $(config_pinned_skills); do
    IFS="$OLDIFS"
    if d="$(config_skill_dir "$nm")" && is_skill_dir "$d"; then
      link_skill "$d" "$dest" "$nm" "$mode"
      record_install "$nm" "$scope" "$project_root" "$tools" "$dest"
    else
      warn "Pinned skill '$nm' has no valid source; skipped."
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
}

install_main() {
  local scope="global" project_root="" keep=0 mode="copy" force=0
  local tools="" targets=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --install) ;;
      # --update is install that overwrites existing skills without prompting.
      # It only touches the named skills, so it implies --keep (no dir clear).
      --update) force=1; keep=1 ;;
      --claude)          tools="$tools claude" ;;
      --antigravity)     tools="$tools antigravity" ;;
      --antigravity-ide) tools="$tools antigravity-ide" ;;
      --keep) keep=1 ;;
      --symlink) mode="symlink" ;;
      -s|--skill)
        [ -n "${2:-}" ] && [ "${2#-}" = "$2" ] \
          || die "$1 requires at least one value, e.g. --skill my-skill"
        shift
        while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do
          targets="${targets:+$targets
}$1"; shift
        done
        continue
        ;;
      -p|--path)
        scope="project"
        if [ -n "${2:-}" ] && [ "${2#-}" = "$2" ]; then
          project_root="$2"; shift
        else
          project_root="."
        fi
        ;;
      *) warn "Ignoring unexpected argument: $1" ;;
    esac
    shift
  done

  [ -n "$targets" ] || die "No target. Use -s/--skill <skill-name-or-category> ..."

  # Default to all tools when none specified.
  [ -n "$tools" ] || tools="$ALL_TOOLS"

  # Resolve project root to an absolute path.
  if [ "$scope" = "project" ]; then
    [ -d "$project_root" ] || die "Project path is not a directory: $project_root"
    project_root="$(cd "$project_root" && pwd)"
  fi

  # Resolve every selector (skill name or category) to skill names, then dirs.
  local OLDIFS="$IFS"
  local names="" t resolved
  IFS='
'
  for t in $targets; do
    IFS="$OLDIFS"
    resolved="$(resolve_selector "$t")"
    names="${names:+$names
}$resolved"
    IFS='
'
  done
  IFS="$OLDIFS"

  # Build a deduped list of destination directories.
  local dests d; dests="$(build_dests "$tools" "$scope" "$project_root")"
  [ -n "$dests" ] || die "No valid destinations resolved"

  local disp; disp="$(printf '%s' "$targets" | tr '\n' ' ')"
  local what="Copying"; [ "$mode" = "symlink" ] && what="Linking"
  [ "$force" -eq 1 ] && what="Updating"
  info "$what '$disp' ($scope) to:"
  IFS='
'
  for d in $dests; do note "  $d"; done

  # Per destination: optionally clear, then install each skill. Use newline-IFS
  # for-loops (not piped while-read) so confirm prompts keep reading the tty.
  for d in $dests; do
    IFS="$OLDIFS"
    mkdir -p "$d"
    if [ "$keep" -ne 1 ]; then
      clear_dir "$d"
      reinstall_pinned_into "$d" "$scope" "$project_root" "$tools" "$mode"
    fi
    local nm sdir
    IFS='
'
    for nm in $names; do
      IFS="$OLDIFS"
      sdir="$(skill_dir_checked "$nm")"
      # If the skill already exists in the target, --install warns and asks
      # before overwriting; --update (force) overwrites silently.
      if [ "$force" -ne 1 ] && [ -e "$d/$nm" ]; then
        if ! confirm "Skill '$nm' already exists in '$d'. Update it?"; then
          note "Skipped: $d/$nm"
          IFS='
'
          continue
        fi
      fi
      link_skill "$sdir" "$d" "$nm" "$mode"
      record_install "$nm" "$scope" "$project_root" "$tools" "$d"
      IFS='
'
    done
    IFS='
'
  done
  IFS="$OLDIFS"

  info "Done."
}
