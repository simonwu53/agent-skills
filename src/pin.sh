#!/usr/bin/env bash
# pin.sh — implements `main.sh --pin ...` and `main.sh --unpin ...`
# Pinning sets `pinned: true` on the skill in config.yaml and installs it now.
# Pinned skills are re-installed into any destination cleared during an install,
# so they survive every clear. Unpinning only clears the flag — use --remove to
# uninstall the copies.

# _parse_pin_args "$@" — shared flag parsing for pin/unpin. Sets:
#   PIN_TARGETS, PIN_TOOLS, PIN_SCOPE, PIN_PATH (path is "" for global scope).
_parse_pin_args() {
  PIN_TARGETS=""; PIN_TOOLS=""; PIN_SCOPE="global"; PIN_PATH=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --pin|--unpin) ;;
      --claude)          PIN_TOOLS="$PIN_TOOLS claude" ;;
      --antigravity)     PIN_TOOLS="$PIN_TOOLS antigravity" ;;
      --antigravity-ide) PIN_TOOLS="$PIN_TOOLS antigravity-ide" ;;
      -s|--skill)
        [ -n "${2:-}" ] && [ "${2#-}" = "$2" ] \
          || die "$1 requires at least one value, e.g. --skill my-skill"
        shift
        while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do
          PIN_TARGETS="${PIN_TARGETS:+$PIN_TARGETS
}$1"; shift
        done
        continue
        ;;
      -p|--path)
        PIN_SCOPE="project"
        if [ -n "${2:-}" ] && [ "${2#-}" = "$2" ]; then
          PIN_PATH="$2"; shift
        else
          PIN_PATH="."
        fi
        ;;
      *) warn "Ignoring unexpected argument: $1" ;;
    esac
    shift
  done

  [ -n "$PIN_TARGETS" ] || die "No target. Use -s/--skill <skill-name-or-category> ..."
  [ -n "$PIN_TOOLS" ] || PIN_TOOLS="$ALL_TOOLS"
  # Strip the leading space left by the accumulator.
  PIN_TOOLS="${PIN_TOOLS#"${PIN_TOOLS%%[![:space:]]*}"}"

  if [ "$PIN_SCOPE" = "project" ]; then
    [ -d "$PIN_PATH" ] || die "Project path is not a directory: $PIN_PATH"
    PIN_PATH="$(cd "$PIN_PATH" && pwd)"
  fi

  # Resolve selectors (skill names or categories) to skill names.
  local OLDIFS="$IFS" sel resolved
  PIN_NAMES=""
  IFS='
'
  for sel in $PIN_TARGETS; do
    IFS="$OLDIFS"
    resolved="$(resolve_selector "$sel")"
    PIN_NAMES="${PIN_NAMES:+$PIN_NAMES
}$resolved"
    IFS='
'
  done
  IFS="$OLDIFS"
}

pin_main() {
  _parse_pin_args "$@"

  local dests d; dests="$(build_dests "$PIN_TOOLS" "$PIN_SCOPE" "$PIN_PATH")"
  [ -n "$dests" ] || die "No valid destinations resolved"

  local OLDIFS="$IFS" nm sdir
  IFS='
'
  for nm in $PIN_NAMES; do
    IFS="$OLDIFS"
    config_set_skill_field "$nm" pinned true
    info "Pinned: $nm"
    # Install it now so it's available immediately (no clearing).
    sdir="$(skill_dir_checked "$nm")"
    IFS='
'
    for d in $dests; do
      IFS="$OLDIFS"
      mkdir -p "$d"
      link_skill "$sdir" "$d" "$nm"
      record_install "$nm" "$PIN_SCOPE" "$PIN_PATH" "$PIN_TOOLS" "$d"
      IFS='
'
    done
  done
  IFS="$OLDIFS"

  info "Done."
}

unpin_main() {
  _parse_pin_args "$@"

  local OLDIFS="$IFS" nm
  IFS='
'
  for nm in $PIN_NAMES; do
    IFS="$OLDIFS"
    if config_skill_is_pinned "$nm"; then
      config_set_skill_field "$nm" pinned false
      info "Unpinned: $nm"
    else
      warn "Not pinned: $nm"
    fi
    IFS='
'
  done
  IFS="$OLDIFS"

  note "Installed copies are left in place; use --remove to uninstall them."
  info "Done."
}
