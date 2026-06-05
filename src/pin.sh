#!/usr/bin/env bash
# pin.sh — implements `main.sh --pin ...` and `main.sh --unpin ...`
# Pins are recorded in config.yaml and re-linked after every install-clear, so a
# pinned skill is always available. Pinning also links it immediately.

# _parse_pin_args "$@" — shared flag parsing for pin/unpin. Sets:
#   PIN_TARGET, PIN_TOOLS, PIN_SCOPE, PIN_PATH (path is "" for global scope).
_parse_pin_args() {
  PIN_TARGET=""; PIN_TOOLS=""; PIN_SCOPE="global"; PIN_PATH=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --pin|--unpin) ;;
      --claude)          PIN_TOOLS="$PIN_TOOLS claude" ;;
      --antigravity)     PIN_TOOLS="$PIN_TOOLS antigravity" ;;
      --antigravity-ide) PIN_TOOLS="$PIN_TOOLS antigravity-ide" ;;
      -s|--skill)
        [ -n "${2:-}" ] || die "$1 requires a value, e.g. --skill Academic/pptx-poster"
        PIN_TARGET="$2"; shift
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

  [ -n "$PIN_TARGET" ] || die "No target. Use -s/--skill [Category] or -s/--skill [Category]/[skill-name]"
  [ -n "$PIN_TOOLS" ] || PIN_TOOLS="$ALL_TOOLS"
  # Strip the leading space left by the accumulator, so it's stored cleanly.
  PIN_TOOLS="${PIN_TOOLS#"${PIN_TOOLS%%[![:space:]]*}"}"

  if [ "$PIN_SCOPE" = "project" ]; then
    [ -d "$PIN_PATH" ] || die "Project path is not a directory: $PIN_PATH"
    PIN_PATH="$(cd "$PIN_PATH" && pwd)"
  fi
}

pin_main() {
  _parse_pin_args "$@"

  # Record the pin first (config_add_pin merges tools into any existing entry).
  config_add_pin "$PIN_TARGET" "$PIN_TOOLS" "$PIN_SCOPE" "$PIN_PATH"
  info "Pinned '$PIN_TARGET' for: $PIN_TOOLS ($PIN_SCOPE)"

  # Then link it now so it's available immediately (no clearing).
  split_target "$PIN_TARGET"
  local skill_dirs; skill_dirs="$(resolve_skill_dirs "$TARGET_CATEGORY" "$TARGET_SKILL")"
  local dests d; dests="$(build_dests "$PIN_TOOLS" "$PIN_SCOPE" "$PIN_PATH")"
  [ -n "$dests" ] || die "No valid destinations resolved"

  local OLDIFS="$IFS"; IFS='
'
  for d in $dests; do
    mkdir -p "$d"
    local s
    for s in $skill_dirs; do link_skill "$s" "$d"; done
  done
  IFS="$OLDIFS"

  info "Done."
}

unpin_main() {
  _parse_pin_args "$@"

  config_is_pinned "$PIN_TARGET" "$PIN_SCOPE" "$PIN_PATH" \
    || warn "'$PIN_TARGET' is not pinned for ($PIN_SCOPE); removing any stray symlinks anyway."

  # Remove the config entry (named tools only) first.
  config_remove_pin "$PIN_TARGET" "$PIN_SCOPE" "$PIN_PATH" "$PIN_TOOLS"
  info "Unpinned '$PIN_TARGET' for: $PIN_TOOLS ($PIN_SCOPE)"

  # Then remove the symlinks the pin created.
  split_target "$PIN_TARGET"
  local skill_dirs names="" s
  skill_dirs="$(resolve_skill_dirs "$TARGET_CATEGORY" "$TARGET_SKILL")"
  local OLDIFS="$IFS"; IFS='
'
  for s in $skill_dirs; do
    names="${names:+$names
}$(basename "$s")"
  done
  IFS="$OLDIFS"

  local dests d; dests="$(build_dests "$PIN_TOOLS" "$PIN_SCOPE" "$PIN_PATH")"
  IFS='
'
  for d in $dests; do
    local n
    for n in $names; do unlink_skill "$n" "$d"; done
  done
  IFS="$OLDIFS"

  info "Done."
}
