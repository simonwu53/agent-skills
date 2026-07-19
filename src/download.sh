#!/usr/bin/env bash
# download.sh — implements `main.sh --load ...` and `main.sh --unload ...`
# GitHub repos are added as git submodules under skills/repository/ and skills
# are registered in config.yaml (repo slug + subpath). Local sources (--path,
# --file) are copied under skills/local/. Skills stay inside their source repo;
# the config db is the single record of what is loaded.

# --- registration ------------------------------------------------------------

# register_skill <name> <repo-slug-or-local> <subpath> <category>
# Adds the skill to the db, enforcing unique names: on a clash with a different
# source, ask to replace the old skill (double-confirmed; the old source is
# cleaned up like --unload) or skip the new one. Returns non-zero when skipped.
register_skill() {
  local name="$1" repo="$2" sub="$3" category="$4"

  local existing
  if existing="$(config_get_skill "$name")"; then
    local e_repo e_sub
    e_repo="$(_skill_field "$existing" 2)"
    e_sub="$(_skill_field "$existing" 3)"
    if [ "$e_repo" = "$repo" ] && [ "$e_sub" = "$sub" ]; then
      config_set_skill_field "$name" category "$category"
      info "Skill '$name' already loaded from $repo; refreshed its entry."
      return 0
    fi
    warn "Skill name clash: '$name' already exists (from: $e_repo)."
    note "Only one skill per name is allowed — one workflow per task."
    if ! confirm "Replace the existing '$name' with the new one (from: $repo)?"; then
      warn "Skipped: $name (kept the existing skill)"
      return 1
    fi
    if ! confirm "Permanently delete the existing '$name' and clean up its source?"; then
      warn "Skipped: $name (kept the existing skill)"
      return 1
    fi
    delete_skill_entry "$name"
  fi

  config_add_skill "$name" "$repo" "$sub" "$category"
  info "Added skill: $name  (category: $category, source: $repo)"
}

# --- GitHub loads ------------------------------------------------------------

# _parse_github_url <url> — sets GH_AUTHOR and GH_REPO, dies on bad input.
_parse_github_url() {
  local url="$1"
  url="${url%/}"; url="${url%.git}"
  case "$url" in
    */tree/*|*/blob/*)
      die "Subfolder links are no longer supported. Give the repo root link and select skills with --skill, e.g.
  main.sh --load --link https://github.com/owner/repo --skill my-skill" ;;
    *github.com/*) ;;
    *) die "Not a GitHub repo URL: $1" ;;
  esac
  local path="${url#*github.com/}"
  GH_AUTHOR="${path%%/*}"
  GH_REPO="${path#*/}"
  [ -n "$GH_AUTHOR" ] && [ -n "$GH_REPO" ] && [ "${GH_REPO#*/}" = "$GH_REPO" ] \
    || die "Expected a repo root link (https://github.com/<owner>/<repo>): $1"
  GH_URL="https://github.com/$GH_AUTHOR/$GH_REPO"
}

# _remove_submodule <rel-path> — deinit and delete a submodule checkout.
_remove_submodule() {
  local rel="$1"
  git -C "$REPO_ROOT" submodule deinit -f "$rel" >/dev/null 2>&1
  git -C "$REPO_ROOT" rm -f "$rel" >/dev/null 2>&1 || rm -rf "$REPO_ROOT/$rel"
  rm -rf "$REPO_ROOT/.git/modules/$rel"
}

load_from_github() {
  local link="$1" category="$2" cat_given="$3" targets="$4"

  _parse_github_url "$link"
  local slug="$GH_AUTHOR/$GH_REPO"
  local rel="$REPOSITORY_DIR/$GH_AUTHOR-$GH_REPO"
  local dir="$REPO_ROOT/$rel"

  # Add the repo as a submodule (once); loading again just registers more skills.
  local added_now=0
  if config_repo_record "$slug" >/dev/null && [ -d "$dir" ]; then
    note "Repo already in library: $rel"
  else
    [ -e "$dir" ] && die "Path exists but is not a loaded repo: $rel"
    mkdir -p "$REPO_ROOT/$REPOSITORY_DIR"
    info "Adding submodule: $slug -> $rel"
    git -C "$REPO_ROOT" submodule add "$GH_URL" "$rel" \
      || die "git submodule add failed for $GH_URL"
    config_add_repo "$GH_AUTHOR" "$GH_REPO" "$GH_URL" "$rel"
    added_now=1
  fi

  local registered=0

  if [ -n "$targets" ]; then
    # --skill: select skills inside the repo's skills folder. "Cat/name" means
    # the repo nests categories; the category is inferred unless --cat is given.
    local skroot
    skroot="$(find_skills_root "$dir")" \
      || die "No skills/skill/SKILLS/SKILL folder found in $slug (needed for --skill)"
    local skroot_name; skroot_name="$(basename "$skroot")"

    local OLDIFS="$IFS" sel
    IFS='
'
    for sel in $targets; do
      IFS="$OLDIFS"
      local src="$skroot/$sel" name cat="$category"
      name="$(basename "$sel")"
      case "$sel" in
        */*) [ "$cat_given" -eq 1 ] || cat="${sel%%/*}" ;;
      esac
      if ! is_skill_dir "$src"; then
        warn "Skipping '$sel': no SKILL.md at $skroot_name/$sel"
      elif register_skill "$name" "$slug" "$skroot_name/$sel" "$cat"; then
        registered=$((registered + 1))
      fi
      IFS='
'
    done
    IFS="$OLDIFS"
  elif is_skill_dir "$dir"; then
    # Auto mode, pattern 1: the repo root is itself a skill.
    info "Repo root is a skill folder."
    if register_skill "$GH_REPO" "$slug" "" "$category"; then
      registered=$((registered + 1))
    fi
  else
    # Auto mode, pattern 2: every subfolder of skills/ is a skill (not a category).
    local skroot
    skroot="$(find_skills_root "$dir")" \
      || die "No SKILL.md at repo root and no skills/skill/SKILLS/SKILL folder in $slug"
    local skroot_name; skroot_name="$(basename "$skroot")"
    info "Found skills folder: $skroot_name"

    local d names="" count=0
    for d in "$skroot"/*/; do
      [ -d "$d" ] || continue
      d="${d%/}"
      if is_skill_dir "$d"; then
        names="${names:+$names
}$(basename "$d")"
        count=$((count + 1))
      else
        note "  (skipping $(basename "$d"): no SKILL.md)"
      fi
    done
    [ "$count" -gt 0 ] || die "No skill folders (with SKILL.md) found in $skroot_name/"

    local OLDIFS="$IFS" n
    if [ "$count" -gt 1 ]; then
      info "Found $count skills in $slug:"
      IFS='
'
      for n in $names; do note "  - $n"; done
      IFS="$OLDIFS"
      confirm "Add all $count skills under category '$category'?" || die "Aborted."
    fi
    IFS='
'
    for n in $names; do
      IFS="$OLDIFS"
      if register_skill "$n" "$slug" "$skroot_name/$n" "$category"; then
        registered=$((registered + 1))
      fi
      IFS='
'
    done
    IFS="$OLDIFS"
  fi

  # Nothing registered from a repo we just added → don't keep the dead weight.
  if [ "$registered" -eq 0 ] && [ "$added_now" -eq 1 ]; then
    warn "No skills registered from $slug; removing the submodule again."
    _remove_submodule "$rel"
    config_remove_repo "$slug"
  fi
}

# find_skills_root <repo-checkout>  -> prints path to skills folder, or fails.
find_skills_root() {
  local repo="$1" d
  for d in skills skill SKILLS SKILL; do
    if [ -d "$repo/$d" ]; then printf '%s\n' "$repo/$d"; return 0; fi
  done
  return 1
}

# --- local loads (--path / --file) -------------------------------------------

# _add_local_skill <src-dir> <name> <category> <source-desc>
_add_local_skill() {
  local src="$1" name="$2" category="$3" source_desc="$4"

  if ! is_skill_dir "$src"; then
    warn "Skipping '$name': no SKILL.md found"
    return 1
  fi

  local rel="$LOCAL_DIR/$name"
  local dest="$REPO_ROOT/$rel"
  if [ -e "$dest" ]; then
    if ! confirm "Local skill '$name' is already stored. Overwrite its source?"; then
      warn "Skipped: $name"
      return 1
    fi
  fi
  # Register first: the unique-name policy (and its prompts) live there.
  register_skill "$name" "local" "" "$category" || return 1
  mkdir -p "$REPO_ROOT/$LOCAL_DIR"
  rm -rf "$dest"
  cp -R "$src" "$dest"
  config_add_local "$name" "$rel" "$source_desc"
  info "Stored local skill: $rel"
}

load_from_path() {
  local path="$1" category="$2"
  [ -d "$path" ] || die "Local path is not a directory: $path"
  local abs; abs="$(cd "$path" && pwd)"
  _add_local_skill "$abs" "$(basename "$abs")" "$category" "$abs"
}

load_from_zip() {
  local file="$1" category="$2"
  [ -f "$file" ] || die "Zip archive not found: $file"
  local tmp; tmp="$(make_tmp)"

  unzip -q "$file" -d "$tmp" || die "Failed to unzip: $file"

  if [ -f "$tmp/SKILL.md" ]; then
    # Archive root *is* the skill folder; derive name from the zip filename.
    local name; name="$(basename "$file")"; name="${name%.zip}"
    _add_local_skill "$tmp" "$name" "$category" "$file"
    return
  fi

  local d found=0
  for d in "$tmp"/*/; do
    [ -d "$d" ] || continue
    [ "$(basename "$d")" = "__MACOSX" ] && continue
    if is_skill_dir "${d%/}"; then
      _add_local_skill "${d%/}" "$(basename "$d")" "$category" "$file" && found=1
    fi
  done
  [ "$found" -eq 1 ] || die "No skill folder (with SKILL.md) found in archive"
}

# --- entry point -------------------------------------------------------------

download_main() {
  local link="" path="" file="" category="Main" cat_given=0 targets=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --load) ;;
      -l|--link) link="$2"; shift ;;
      -p|--path) path="$2"; shift ;;
      -f|--file) file="$2"; shift ;;
      -c|--cat)  category="$2"; cat_given=1; shift ;;
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
      --merge) die "--merge has been removed; every skill now records its own category" ;;
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
    load_from_github "$link" "$category" "$cat_given" "$targets"
  elif [ -n "$path" ]; then
    load_from_path "$path" "$category"
  else
    load_from_zip "$file" "$category"
  fi
}

# --- unload ------------------------------------------------------------------

# delete_skill_entry <name> — remove a skill from the db and clean up its
# source: local dirs are deleted; a repo submodule is removed once its last
# skill goes (with a confirm). Callers own the outer deletion confirmation.
delete_skill_entry() {
  local name="$1"
  local r; r="$(config_get_skill "$name")" || { warn "Not in library: $name"; return 1; }
  local repo; repo="$(_skill_field "$r" 2)"

  config_remove_skill "$name"

  if [ "$repo" = "local" ]; then
    rm -rf "$REPO_ROOT/$LOCAL_DIR/$name"
    config_remove_local "$name"
    info "Deleted local source: $LOCAL_DIR/$name"
  else
    if ! config_skills_in_repo "$repo" >/dev/null; then
      local rel; rel="$(config_repo_path "$repo")"
      if [ -n "$rel" ] && confirm "Repo '$repo' has no skills left. Remove its submodule ($rel)?"; then
        _remove_submodule "$rel"
        config_remove_repo "$repo"
        info "Removed submodule: $rel"
      else
        note "Kept repo checkout: $repo"
      fi
    fi
  fi
  info "Unloaded skill: $name"
}

# unload_main — implements `main.sh --unload ...`. The inverse of --load: drop
# skill(s) from the db and delete/clean up their sources.
unload_main() {
  local targets=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --unload) ;;
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
      *) warn "Ignoring unexpected argument: $1" ;;
    esac
    shift
  done

  [ -n "$targets" ] || die "No target. Use -s/--skill <skill-name-or-category> ..."

  # Resolve every selector (skill name or category) to skill names.
  local OLDIFS="$IFS" sel names="" resolved
  IFS='
'
  for sel in $targets; do
    IFS="$OLDIFS"
    resolved="$(resolve_selector "$sel")"
    names="${names:+$names
}$resolved"
    IFS='
'
  done
  IFS="$OLDIFS"

  info "About to UNLOAD from the library:"
  local nm pinned_any=0
  IFS='
'
  for nm in $names; do
    IFS="$OLDIFS"
    if config_skill_is_pinned "$nm"; then
      note "  $nm (PINNED)"; pinned_any=1
    else
      note "  $nm"
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
  [ "$pinned_any" -eq 1 ] && warn "Some of these skills are pinned."

  confirm "Permanently delete the above from the library?" || die "Aborted."

  IFS='
'
  for nm in $names; do
    IFS="$OLDIFS"
    delete_skill_entry "$nm"
    IFS='
'
  done
  IFS="$OLDIFS"

  note "Any symlinks elsewhere that pointed at these sources will now dangle."
  info "Done."
}
