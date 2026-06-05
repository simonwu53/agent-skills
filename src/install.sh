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
          || die "$1 requires at least one value, e.g. --skill Academic/pptx-poster"
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

  [ -n "$targets" ] || die "No target. Use -s/--skill [Category] or -s/--skill [Category]/[skill-name]"

  # Default to all tools when none specified.
  [ -n "$tools" ] || tools="$ALL_TOOLS"

  # Resolve project root to an absolute path.
  if [ "$scope" = "project" ]; then
    [ -d "$project_root" ] || die "Project path is not a directory: $project_root"
    project_root="$(cd "$project_root" && pwd)"
  fi

  # Resolve skill dirs across every --skill selector (each Category or Category/skill).
  local OLDIFS="$IFS"
  local skill_dirs="" t resolved
  IFS='
'
  for t in $targets; do
    IFS="$OLDIFS"
    split_target "$t"
    resolved="$(resolve_skill_dirs "$TARGET_CATEGORY" "$TARGET_SKILL")"
    skill_dirs="${skill_dirs:+$skill_dirs
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
    mkdir -p "$d"
    if [ "$keep" -ne 1 ]; then
      clear_dir "$d"
      relink_pins_into "$d" "$scope" "$project_root" "$mode"
    fi
    local s
    for s in $skill_dirs; do
      # If the skill already exists in the target, --install warns and asks
      # before overwriting; --update (force) overwrites silently.
      local sname; sname="$(basename "$s")"
      if [ "$force" -ne 1 ] && [ -e "$d/$sname" ]; then
        if ! confirm "Skill '$sname' already exists in '$d'. Update it?"; then
          note "Skipped: $d/$sname"
          continue
        fi
      fi
      link_skill "$s" "$d" "$mode"
    done
  done
  IFS="$OLDIFS"

  info "Done."
}

# relink_pins_into <dest-dir> <scope> <project-root> [mode]
# After a clear, re-install any pinned skills that map to <dest-dir> (using the
# install run's copy/symlink mode), so pins are always available. Tolerates pins
# whose source was since removed (--unload).
relink_pins_into() {
  local dest="$1" scope="$2" project_root="$3" mode="${4:-copy}"
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
          for s in $pdirs; do link_skill "$s" "$dest" "$mode"; done
          IFS="$IFS2"
        fi
      fi
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
}
