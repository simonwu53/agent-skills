#!/usr/bin/env bash
# remove.sh — implements `main.sh --remove ...`
# Removes skill symlinks previously created by `install`.

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
          || die "$1 requires at least one value, e.g. --skill pptx-poster"
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

  # Detect pins protecting this removal. `strip` holds single-skill pins whose
  # config should be cleaned (skill<SEP>intersecting-tools, one per line);
  # category-level pins are warned about but left intact. With --remove-all every
  # pin for the targeted tools/scope is considered matched.
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
        local matched=0
        if [ "$remove_all" -eq 1 ]; then
          matched=1
        else
          # Does the pin's skill selector cover any name being removed?
          local pcat psk pdirs pn
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
        fi
        if [ "$matched" -eq 1 ]; then
          pin_warn="${pin_warn}
  $rs (tools: $hitt)"
          # Strip only single-skill pins (Category/skill); leave category pins.
          case "$rs" in
            */*) strip="${strip:+$strip
}$rs$_SEP$hitt" ;;
          esac
        fi
      fi
    fi
    IFS='
'
  done
  IFS="$OLDIFS"

  if [ -n "$pin_warn" ]; then
    warn "This removal targets PINNED skill(s):${pin_warn}"
    note "Confirming will also delete the matching single-skill pin config (category-level pins are left intact — use --unpin to clear those)."
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
    if [ "$remove_all" -eq 1 ]; then
      remove_all_skills "$d"
    else
      local n
      for n in $names; do
        unlink_skill "$n" "$d"
      done
    fi
  done
  IFS="$OLDIFS"

  info "Done."
}
