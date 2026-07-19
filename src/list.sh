#!/usr/bin/env bash
# list.sh — implements `main.sh --list ...`
# With no target flag: list the library from config.yaml, grouped by category.
# With a tool flag (and/or -p): list the skills installed for that tool/scope.

list_main() {
  local scope="global" project_root="" tools="" target_given=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --list) ;;
      --claude)          tools="$tools claude"; target_given=1 ;;
      --antigravity)     tools="$tools antigravity"; target_given=1 ;;
      --antigravity-ide) tools="$tools antigravity-ide"; target_given=1 ;;
      -p|--path)
        scope="project"; target_given=1
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

  # No tool flag and no project path → list the library.
  if [ "$target_given" -eq 0 ]; then
    list_library
    return 0
  fi

  # Otherwise list installed skills for the targeted tool(s)/scope.
  [ -n "$tools" ] || tools="$ALL_TOOLS"
  if [ "$scope" = "project" ]; then
    [ -d "$project_root" ] || die "Project path is not a directory: $project_root"
    project_root="$(cd "$project_root" && pwd)"
  fi
  list_installed "$tools" "$scope" "$project_root"
}

# list_library — print every skill recorded in config.yaml, grouped by category.
list_library() {
  local records; records="$(config_read_skills)"
  info "Skills in library ($(basename "$CONFIG_FILE")):"
  if [ -z "$records" ]; then
    note "  (no skills loaded)"
    return 0
  fi

  # Collect the unique categories, then print each group.
  local OLDIFS="$IFS" r cats="" c
  IFS='
'
  for r in $records; do
    IFS="$OLDIFS"
    c="$(_skill_field "$r" 4)"
    _in_list "$cats" "$c" || cats="${cats:+$cats
}$c"
    IFS='
'
  done
  for c in $cats; do
    IFS="$OLDIFS"
    printf '%s\n' "  $c/"
    local IFS2="$IFS"; IFS='
'
    for r in $records; do
      IFS="$IFS2"
      [ "$(_skill_field "$r" 4)" = "$c" ] || { IFS='
'; continue; }
      local name repo pin mark=""
      name="${r%%"$_SEP"*}"
      repo="$(_skill_field "$r" 2)"
      pin="$(_skill_field "$r" 5)"
      [ "$pin" = "true" ] && mark=" (pinned)"
      printf '%s\n' "    - $name  [$repo]$mark"
      IFS='
'
    done
    IFS='
'
  done
  IFS="$OLDIFS"
}

# list_installed <tools> <scope> <project-root> — print the managed skills (copies
# or symlinks) installed in each tool's skills dir. Dedupes shared dirs.
list_installed() {
  local tools="$1" scope="$2" project_root="$3"
  local t dir seen=""
  for t in $tools; do
    if [ "$scope" = "global" ]; then
      dir="$(global_dir_for_tool "$t")" || { warn "Unknown tool: $t"; continue; }
    else
      dir="$(project_dir_for_tool "$t" "$project_root")" || { warn "Unknown tool: $t"; continue; }
    fi
    # Several tools can share one dir (e.g. project-scoped antigravity/-ide).
    _in_list "$seen" "$dir" && continue
    seen="${seen:+$seen
}$dir"

    info "$t ($scope): $dir"
    if [ ! -d "$dir" ]; then
      note "  (directory does not exist)"
      continue
    fi
    local entry found=0
    for entry in "$dir"/*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      local name; name="$(basename "$entry")"
      if [ -L "$entry" ]; then
        printf '%s\n' "    - $name (symlink)"; found=1
      elif [ -d "$entry" ] && is_skill_dir "$entry"; then
        printf '%s\n' "    - $name (copy)"; found=1
      fi
    done
    [ "$found" -eq 1 ] || note "  (no skills installed)"
  done
}
