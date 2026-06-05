#!/usr/bin/env bash
# remove.sh — implements `main.sh --remove ...`
# Removes skill symlinks previously created by `install`.

remove_main() {
  local target="" scope="global" project_root=""
  local tools=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --remove) ;;
      --claude)          tools="$tools claude" ;;
      --antigravity)     tools="$tools antigravity" ;;
      --antigravity-ide) tools="$tools antigravity-ide" ;;
      -s|--skill)
        [ -n "${2:-}" ] || die "$1 requires a value, e.g. --skill Academic/pptx-poster"
        target="$2"; shift
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

  [ -n "$target" ] || die "No target. Use -s/--skill [Category] or -s/--skill [Category]/[skill-name]"
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
  local dests d; dests="$(build_dests "$tools" "$scope" "$project_root")"
  [ -n "$dests" ] || die "No valid destinations resolved"

  info "About to remove '$target' ($scope) from:"
  IFS='
'
  for d in $dests; do note "  $d"; done
  IFS="$OLDIFS"

  # Detect pins protecting this removal. `strip` holds exact-selector pins whose
  # config should be cleaned (skill<SEP>intersecting-tools, one per line).
  local pin_warn="" strip="" r
  IFS='
'
  for r in $(config_read_pins); do
    IFS="$OLDIFS"
    local rs rt rsc rp rest
    rs="${r%%"$_SEP"*}"; rest="${r#*"$_SEP"}"
    rt="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    rsc="${rest%%"$_SEP"*}"; rp="${rest#*"$_SEP"}"
    if [ "$rsc" = "$scope" ] && { [ "$scope" = "global" ] || [ "$rp" = "$project_root" ]; }; then
      # Tool intersection between this pin and the removal request.
      local hitt="" t
      for t in $tools; do _in_list_sp "$rt" "$t" && hitt="${hitt:+$hitt }$t"; done
      if [ -n "$hitt" ]; then
        # Does the pin's skill selector cover any name being removed?
        local pcat psk pdirs pn matched=0
        case "$rs" in
          */*) pcat="${rs%%/*}"; psk="${rs#*/}" ;;
          *)   pcat="$rs";        psk="" ;;
        esac
        if pdirs="$(resolve_skill_dirs_soft "$pcat" "$psk")"; then
          local IFS3="$IFS"; IFS='
'
          for pn in $pdirs; do
            _in_list "$names" "$(basename "$pn")" && matched=1
          done
          IFS="$IFS3"
        fi
        if [ "$matched" -eq 1 ]; then
          pin_warn="${pin_warn}
  $rs (tools: $hitt)"
          [ "$rs" = "$target" ] && strip="${strip:+$strip
}$rs$_SEP$hitt"
        fi
      fi
    fi
    IFS='
'
  done
  IFS="$OLDIFS"

  if [ -n "$pin_warn" ]; then
    warn "This removal targets PINNED skill(s):${pin_warn}"
    note "Confirming will also delete the matching pin config (category-level pins are left intact — use --unpin to clear those)."
    confirm "Remove pinned skill(s) and delete their pin config?" || die "Aborted (pinned)."
    local cfg_path=""; [ "$scope" = "project" ] && cfg_path="$project_root"
    IFS='
'
    for r in $strip; do
      local s_skill s_tools
      s_skill="${r%%"$_SEP"*}"; s_tools="${r#*"$_SEP"}"
      config_remove_pin "$s_skill" "$scope" "$cfg_path" "$s_tools"
    done
    IFS="$OLDIFS"
  else
    confirm "Proceed with removal?" || die "Aborted."
  fi

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
