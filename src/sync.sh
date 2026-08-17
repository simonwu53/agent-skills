#!/usr/bin/env bash
# sync.sh — implements `main.sh --sync ...`
# Refreshes loaded repo sources (git submodules under skills/repository/) to the
# latest commit of their remote branch — like `apt update` for the library.
# Only the library is touched: installed copies in tool dirs are NOT refreshed
# (run `--update --skill ...` afterwards for that). Updated submodule pointers
# are staged in the superproject but never committed.
#
#   main.sh --sync                       refresh every loaded repo
#   main.sh --sync --repo author/name    refresh only the given repo(s)

sync_main() {
  local targets=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --sync) ;;
      -r|--repo)
        [ -n "${2:-}" ] && [ "${2#-}" = "$2" ] \
          || die "$1 requires at least one value, e.g. --repo author/name"
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

  local records; records="$(config_read_repos)"
  [ -n "$records" ] || { info "No repos loaded — nothing to sync."; return 0; }

  # Validate explicit targets against the db.
  local OLDIFS="$IFS" t
  if [ -n "$targets" ]; then
    IFS='
'
    for t in $targets; do
      IFS="$OLDIFS"
      config_repo_record "$t" >/dev/null || die "Repo not loaded: $t (use author/name, see --list)"
      IFS='
'
    done
    IFS="$OLDIFS"
  fi

  local n_updated=0 n_current=0 n_failed=0 r slug path rest
  IFS='
'
  for r in $records; do
    IFS="$OLDIFS"
    slug="${r%%"$_SEP"*}"; rest="${r#*"$_SEP"}"; rest="${rest#*"$_SEP"}"
    path="${rest%%"$_SEP"*}"

    if [ -n "$targets" ]; then
      case "$targets" in
        "$slug"|"$slug"$'\n'*|*$'\n'"$slug"|*$'\n'"$slug"$'\n'*) ;;
        *) IFS='
'; continue ;;
      esac
    fi

    if [ ! -d "$REPO_ROOT/$path/.git" ] && [ ! -f "$REPO_ROOT/$path/.git" ]; then
      warn "$slug: submodule not initialized at $path — run: git submodule update --init $path"
      n_failed=$((n_failed + 1)); IFS='
'; continue
    fi

    local before after
    before="$(git -C "$REPO_ROOT/$path" rev-parse --short HEAD 2>/dev/null || echo '?')"
    if git -C "$REPO_ROOT" submodule update --remote --quiet -- "$path" 2>/dev/null; then
      after="$(git -C "$REPO_ROOT/$path" rev-parse --short HEAD 2>/dev/null || echo '?')"
      if [ "$before" = "$after" ]; then
        note "    $slug: up to date ($after)"
        n_current=$((n_current + 1))
      else
        info "$slug: $before -> $after"
        git -C "$REPO_ROOT" add -- "$path" 2>/dev/null || true
        config_repo_touch "$slug"
        n_updated=$((n_updated + 1))
      fi
    else
      err "$slug: failed to fetch/update ($path)"
      n_failed=$((n_failed + 1))
    fi
    IFS='
'
  done
  IFS="$OLDIFS"

  info "Sync done: $n_updated updated, $n_current up to date, $n_failed failed."
  if [ "$n_updated" -gt 0 ]; then
    note "Updated submodule pointers are staged (not committed)."
    note "Installed copies are unchanged — refresh them with: main.sh --update --skill <name> ..."
  fi
  [ "$n_failed" -eq 0 ]
}
