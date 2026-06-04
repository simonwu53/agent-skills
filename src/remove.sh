#!/usr/bin/env bash
# remove.sh — implements `main.sh --remove ...`
# Removes skill symlinks previously created by `install`.

# unlink_skill <name> <dest-dir>
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

remove_main() {
  local target="" scope="global" project_root=""
  local tools=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --remove) ;;
      --claude)          tools="$tools claude" ;;
      --antigravity)     tools="$tools antigravity" ;;
      --antigravity-ide) tools="$tools antigravity-ide" ;;
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
  [ -n "$tools" ] || tools="$ALL_TOOLS"

  if [ "$scope" = "project" ]; then
    [ -d "$project_root" ] || die "Project path is not a directory: $project_root"
    project_root="$(cd "$project_root" && pwd)"
  fi

  split_target "$target"

  # Resolve the skill name(s) to remove from the repo definitions.
  local skill_dirs names="" s
  skill_dirs="$(resolve_skill_dirs "$TARGET_CATEGORY" "$TARGET_SKILL")"
  local OLDIFS="$IFS"; IFS='
'
  for s in $skill_dirs; do
    names="${names:+$names
}$(basename "$s")"
  done
  IFS="$OLDIFS"

  # Build deduped destination list.
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

  info "About to remove '$target' ($scope) from:"
  IFS='
'
  for d in $dests; do note "  $d"; done
  IFS="$OLDIFS"

  confirm "Proceed with removal?" || die "Aborted."

  IFS='
'
  for d in $dests; do
    local n
    for n in $names; do
      unlink_skill "$n" "$d"
    done
  done
  IFS="$OLDIFS"

  info "Done."
}
