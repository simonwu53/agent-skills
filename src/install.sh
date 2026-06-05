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
      -s|--skill)
        [ -n "${2:-}" ] || die "$1 requires a value, e.g. --skill Academic/pptx-poster"
        target="$2"; shift
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

  [ -n "$target" ] || die "No target. Use -s/--skill [Category] or -s/--skill [Category]/[skill-name]"

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
  local dests d; dests="$(build_dests "$tools" "$scope" "$project_root")"
  [ -n "$dests" ] || die "No valid destinations resolved"

  info "Installing '$target' ($scope) to:"
  local OLDIFS="$IFS"; IFS='
'
  for d in $dests; do note "  $d"; done

  # Per destination: optionally clear, then symlink each skill. Use newline-IFS
  # for-loops (not piped while-read) so confirm prompts keep reading the tty.
  for d in $dests; do
    mkdir -p "$d"
    if [ "$keep" -ne 1 ]; then
      clear_dir "$d"
      relink_pins_into "$d" "$scope" "$project_root"
    fi
    local s
    for s in $skill_dirs; do
      link_skill "$s" "$d"
    done
  done
  IFS="$OLDIFS"

  info "Done."
}

# relink_pins_into <dest-dir> <scope> <project-root>
# After a clear, re-link any pinned skills that map to <dest-dir>, so pins are
# always available. Tolerates pins whose source was since removed (--unload).
relink_pins_into() {
  local dest="$1" scope="$2" project_root="$3"
  local OLDIFS="$IFS" r
  IFS='
'
  for r in $(config_read_pins); do
    IFS="$OLDIFS"
    local rs rt rsc rp rest
    rs="${r%%"$_SEP"*}"; rest="${r#*"$_SEP"}"
    rt="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    rsc="${rest%%"$_SEP"*}"; rp="${rest#*"$_SEP"}"
    if [ "$rsc" = "$scope" ] && { [ "$scope" = "global" ] || [ "$rp" = "$project_root" ]; }; then
      local t hit=0
      for t in $rt; do
        [ "$(_record_dir_for_tool "$t" "$rsc" "$rp")" = "$dest" ] && { hit=1; break; }
      done
      if [ "$hit" -eq 1 ]; then
        local pcat psk pdirs s
        case "$rs" in
          */*) pcat="${rs%%/*}"; psk="${rs#*/}" ;;
          *)   pcat="$rs";        psk="" ;;
        esac
        if pdirs="$(resolve_skill_dirs_soft "$pcat" "$psk")"; then
          local IFS2="$IFS"; IFS='
'
          for s in $pdirs; do link_skill "$s" "$dest"; done
          IFS="$IFS2"
        fi
      fi
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
}
