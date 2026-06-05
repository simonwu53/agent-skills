#!/usr/bin/env bash
# download.sh — implements `main.sh --load ...`
# Sources: GitHub repo link, GitHub skill-folder link, local folder, zip archive.

# copy_skill_into_category <src-dir> <category> [name]
# Validates SKILL.md, then copies the folder into repo skills/<category>/<name>.
copy_skill_into_category() {
  local src="$1" category="$2"
  local name="${3:-$(basename "$1")}"

  if ! is_skill_dir "$src"; then
    warn "Skipping '$name': no SKILL.md found"
    return 1
  fi

  local destcat="$REPO_ROOT/skills/$category"
  mkdir -p "$destcat"
  local dest="$destcat/$name"

  if [ -e "$dest" ]; then
    if ! confirm "Skill '$category/$name' already exists. Overwrite?"; then
      warn "Skipped: $category/$name"
      return 1
    fi
    rm -rf "$dest"
  fi

  cp -R "$src" "$dest"
  info "Added skill: $category/$name"
}

# merge_categories <skills-root>
# Source layout: <root>/<category>/<skill>/SKILL.md  -> merge into repo skills/.
merge_categories() {
  local root="$1" category cat_name skill skill_name added=0
  for category in "$root"/*/; do
    [ -d "$category" ] || continue
    cat_name="$(basename "$category")"
    [ "$cat_name" = "__MACOSX" ] && continue
    for skill in "$category"*/; do
      [ -d "$skill" ] || continue
      skill_name="$(basename "$skill")"
      if copy_skill_into_category "${skill%/}" "$cat_name" "$skill_name"; then
        added=1
      fi
    done
  done
  [ "$added" -eq 1 ] || warn "No skills merged from source"
}

# categorize_flat <skills-root> <category>
# Source layout: <root>/<skill>/SKILL.md  -> place each skill under <category>.
categorize_flat() {
  local root="$1" category="$2" skill skill_name added=0
  for skill in "$root"/*/; do
    [ -d "$skill" ] || continue
    skill_name="$(basename "$skill")"
    [ "$skill_name" = "__MACOSX" ] && continue
    if copy_skill_into_category "${skill%/}" "$category" "$skill_name"; then
      added=1
    fi
  done
  [ "$added" -eq 1 ] || warn "No skills added from source"
}

# find_skills_root <repo-checkout>  -> prints path to skills folder, or fails.
find_skills_root() {
  local repo="$1" d
  for d in skills skill SKILLS SKILL; do
    if [ -d "$repo/$d" ]; then printf '%s\n' "$repo/$d"; return 0; fi
  done
  return 1
}

load_from_github() {
  local link="$1" category="$2" merge="$3"
  local url="${link%/}"; url="${url%.git}"
  local tmp; tmp="$(make_tmp)"

  if [ "${url#*/tree/}" != "$url" ]; then
    # Subfolder link: https://github.com/<owner>/<repo>/tree/<branch>/<subpath>
    local base rest branch subpath
    base="${url%%/tree/*}"
    rest="${url#*/tree/}"
    branch="${rest%%/*}"
    if [ "$rest" = "$branch" ]; then
      subpath=""
    else
      subpath="${rest#*/}"
    fi
    [ -n "$subpath" ] || die "GitHub link points to a branch, not a skill folder: $link"

    info "Cloning skill folder from $base ($branch:$subpath)"
    git clone --depth 1 --filter=blob:none --sparse -b "$branch" "$base" "$tmp/repo" \
      || die "git clone failed for $base (branch $branch)"
    git -C "$tmp/repo" sparse-checkout set "$subpath" \
      || die "sparse-checkout failed for $subpath"
    [ -d "$tmp/repo/$subpath" ] || die "Subfolder not found in repo: $subpath"
    copy_skill_into_category "$tmp/repo/$subpath" "$category"
  else
    # Repo-root link.
    info "Cloning repo $url"
    git clone --depth 1 --filter=blob:none --sparse "$url" "$tmp/repo" \
      || die "git clone failed for $url"
    git -C "$tmp/repo" sparse-checkout set skills skill SKILLS SKILL >/dev/null 2>&1

    local skroot
    skroot="$(find_skills_root "$tmp/repo")" \
      || die "No skills/skill/SKILLS/SKILL folder found in repo root"
    info "Found skills folder: $(basename "$skroot")"

    if [ "$merge" -eq 1 ]; then
      merge_categories "$skroot"
    else
      categorize_flat "$skroot" "$category"
    fi
  fi
}

load_from_path() {
  local path="$1" category="$2"
  [ -d "$path" ] || die "Local path is not a directory: $path"
  copy_skill_into_category "$path" "$category"
}

load_from_zip() {
  local file="$1" category="$2"
  [ -f "$file" ] || die "Zip archive not found: $file"
  local tmp; tmp="$(make_tmp)"

  unzip -q "$file" -d "$tmp" || die "Failed to unzip: $file"

  if [ -f "$tmp/SKILL.md" ]; then
    # Archive root *is* the skill folder; derive name from the zip filename.
    local name; name="$(basename "$file")"; name="${name%.zip}"
    copy_skill_into_category "$tmp" "$category" "$name"
    return
  fi

  local d found=0
  for d in "$tmp"/*/; do
    [ -d "$d" ] || continue
    [ "$(basename "$d")" = "__MACOSX" ] && continue
    if is_skill_dir "${d%/}"; then
      copy_skill_into_category "${d%/}" "$category" && found=1
    fi
  done
  [ "$found" -eq 1 ] || die "No skill folder (with SKILL.md) found in archive"
}

download_main() {
  local link="" path="" file="" category="Main" merge=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --load) ;;
      -l|--link) link="$2"; shift ;;
      -p|--path) path="$2"; shift ;;
      -f|--file) file="$2"; shift ;;
      -c|--cat)  category="$2"; shift ;;
      --merge)   merge=1 ;;
      *) warn "Ignoring unexpected argument: $1" ;;
    esac
    shift
  done

  local n=0
  [ -n "$link" ] && n=$((n + 1))
  [ -n "$path" ] && n=$((n + 1))
  [ -n "$file" ] && n=$((n + 1))
  [ "$n" -eq 1 ] || die "Provide exactly one source: --link, --path, or --file"

  if [ -n "$link" ]; then
    load_from_github "$link" "$category" "$merge"
  elif [ -n "$path" ]; then
    load_from_path "$path" "$category"
  else
    load_from_zip "$file" "$category"
  fi
}

# unload_main — implements `main.sh --unload ...`. The inverse of --load: delete
# a skill's (or whole category's) source from the repo skills/ library.
unload_main() {
  local target=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --unload) ;;
      -s|--skill)
        [ -n "${2:-}" ] || die "$1 requires a value, e.g. --skill Academic/pptx-poster"
        target="$2"; shift
        ;;
      *) warn "Ignoring unexpected argument: $1" ;;
    esac
    shift
  done

  [ -n "$target" ] || die "No target. Use -s/--skill [Category] or -s/--skill [Category]/[skill-name]"

  split_target "$target"
  local skill_dirs s; skill_dirs="$(resolve_skill_dirs "$TARGET_CATEGORY" "$TARGET_SKILL")"

  info "About to DELETE source from the repo for '$target':"
  local OLDIFS="$IFS"; IFS='
'
  for s in $skill_dirs; do note "  $s"; done
  IFS="$OLDIFS"

  confirm "Permanently delete the above skill source?" || die "Aborted."

  IFS='
'
  for s in $skill_dirs; do
    rm -rf "$s"
    info "Deleted source: $s"
  done
  IFS="$OLDIFS"

  # Remove the category dir if it is now empty.
  local catdir="$REPO_ROOT/skills/$TARGET_CATEGORY"
  if [ -d "$catdir" ] && [ -z "$(ls -A "$catdir" 2>/dev/null)" ]; then
    rmdir "$catdir"
    note "Removed empty category: $TARGET_CATEGORY"
  fi

  # Strip any pin config covering what we just deleted.
  if config_remove_pins_matching "$target"; then
    warn "Also removed pin config for '$target'."
  fi

  note "Any symlinks elsewhere that pointed at these sources will now dangle."
  info "Done."
}
