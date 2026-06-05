#!/usr/bin/env bash
# list.sh — implements `main.sh --list ...`
# With no target flag: list the repo's skill library, grouped by category.
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

  # No tool flag and no project path → list the repo's library.
  if [ "$target_given" -eq 0 ]; then
    list_repo
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

# list_repo — print every skill in this repo's skills/, grouped by category.
list_repo() {
  local base="$REPO_ROOT/skills"
  [ -d "$base" ] || { warn "No skills/ directory in repo: $base"; return 0; }
  info "Skills in repo ($base):"
  local cat d s found=0
  for cat in "$base"/*/; do
    [ -d "$cat" ] || continue
    cat="${cat%/}"
    local skills=""
    for d in "$cat"/*/; do
      [ -d "$d" ] || continue
      d="${d%/}"
      is_skill_dir "$d" && skills="${skills:+$skills }$(basename "$d")"
    done
    if [ -n "$skills" ]; then
      printf '%s\n' "  $(basename "$cat")/"
      for s in $skills; do printf '%s\n' "    - $s"; done
      found=1
    fi
  done
  [ "$found" -eq 1 ] || note "  (no skills found)"
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
