#!/usr/bin/env bash
# remove.sh — implements `main.sh --remove ...`
# Removes installed skills (copies or symlinks) from agent tool skill
# directories and updates each skill's install state in config.yaml.

# record_removal <name> <scope> <project-root> <tools> <dest>
# Drop the tool/project from the skill's install state (ignores unknown names).
record_removal() {
  local name="$1" scope="$2" project_root="$3" tools="$4" dest="$5" t
  config_skill_exists "$name" || return 0
  if [ "$scope" = "global" ]; then
    for t in $tools; do
      [ "$(global_dir_for_tool "$t")" = "$dest" ] && config_skill_remove_agent "$name" "$t"
    done
  else
    config_skill_remove_project "$name" "$project_root"
  fi
}

remove_main() {
  local scope="global" project_root=""
  local tools="" names="" remove_all=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --remove) ;;
      --claude)          tools="$tools claude" ;;
      --antigravity)     tools="$tools antigravity" ;;
      --antigravity-ide) tools="$tools antigravity-ide" ;;
      -s|--skill)
        [ -n "${2:-}" ] && [ "${2#-}" = "$2" ] \
          || die "$1 requires at least one value, e.g. --skill my-skill"
        shift
        while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do
          names="${names:+$names
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

  # No --skill given → remove every skill installed for the targeted tool(s).
  [ -n "$names" ] || remove_all=1
  [ -n "$tools" ] || tools="$ALL_TOOLS"

  if [ "$scope" = "project" ]; then
    [ -d "$project_root" ] || die "Project path is not a directory: $project_root"
    project_root="$(cd "$project_root" && pwd)"
  fi

  # Build deduped destination list.
  local dests d; dests="$(build_dests "$tools" "$scope" "$project_root")"
  [ -n "$dests" ] || die "No valid destinations resolved"

  local OLDIFS="$IFS"
  if [ "$remove_all" -eq 1 ]; then
    info "About to remove ALL skills ($scope) from:"
  else
    local disp; disp="$(printf '%s' "$names" | tr '\n' ' ')"
    info "About to remove '$disp' ($scope) from:"
  fi
  IFS='
'
  for d in $dests; do note "  $d"; done
  IFS="$OLDIFS"

  # Pinned skills covered by this removal: warn, and unpin them on confirm
  # (otherwise the next install-clear would just bring them back).
  local pinned="" nm
  IFS='
'
  for nm in $(config_pinned_skills); do
    IFS="$OLDIFS"
    if [ "$remove_all" -eq 1 ] || _in_list "$names" "$nm"; then
      pinned="${pinned:+$pinned
}$nm"
    fi
    IFS='
'
  done
  IFS="$OLDIFS"

  if [ -n "$pinned" ]; then
    local pdisp; pdisp="$(printf '%s' "$pinned" | tr '\n' ' ')"
    warn "This removal targets PINNED skill(s): $pdisp"
    note "Confirming will also unpin them (set pinned: false); otherwise the next install-clear re-installs them."
    confirm "Remove pinned skill(s) and unpin them?" || die "Aborted (pinned)."
    IFS='
'
    for nm in $pinned; do
      IFS="$OLDIFS"
      config_set_skill_field "$nm" pinned false
      IFS='
'
    done
    IFS="$OLDIFS"
  else
    confirm "Proceed with removal?" || die "Aborted."
  fi

  IFS='
'
  for d in $dests; do
    IFS="$OLDIFS"
    if [ "$remove_all" -eq 1 ]; then
      local entry
      for entry in "$d"/*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        local en; en="$(basename "$entry")"
        unlink_skill "$en" "$d"
        record_removal "$en" "$scope" "$project_root" "$tools" "$d"
      done
    else
      local n
      IFS='
'
      for n in $names; do
        IFS="$OLDIFS"
        unlink_skill "$n" "$d"
        record_removal "$n" "$scope" "$project_root" "$tools" "$d"
        IFS='
'
      done
      IFS="$OLDIFS"
    fi
    IFS='
'
  done
  IFS="$OLDIFS"

  info "Done."
}
