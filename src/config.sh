#!/usr/bin/env bash
# config.sh — machine-local configuration (config.yaml) for the skills manager.
# Sourced by common.sh. Bash 3.2 / Zsh compatible. Pure-bash YAML handling for a
# deliberately constrained schema (see README). Holds the "pins" feature today;
# top-level keys are namespaced so future features can add their own sections.

# Config file path. Overridable via the CONFIG_FILE env var (used by tests).
CONFIG_FILE="${CONFIG_FILE:-$REPO_ROOT/config.yaml}"

# Internal field separator for the record format emitted by config_read_pins:
#   skill<SEP>tools<SEP>scope<SEP>path     (one record per line)
_SEP=$'\t'

# --- init --------------------------------------------------------------------

# init_config — create config.yaml (with an empty pins block) if missing, and make
# sure the default config.yaml is git-ignored. Safe to call on every invocation.
init_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<'EOF'
# 533s-skills configuration — machine-local, not version controlled.
# Managed by main.sh. Keep the structure if editing by hand.
version: 1

pins:
EOF
  fi
  _ensure_gitignore_config
}

# Add config.yaml to the repo .gitignore once (only for the default config name).
_ensure_gitignore_config() {
  local name; name="$(basename "$CONFIG_FILE")"
  [ "$name" = "config.yaml" ] || return 0
  local gi="$REPO_ROOT/.gitignore"
  if [ -f "$gi" ]; then
    grep -qxF "config.yaml" "$gi" 2>/dev/null && return 0
    printf '\n# Local manager config (machine-specific)\nconfig.yaml\n' >> "$gi"
  else
    printf '# Local manager config (machine-specific)\nconfig.yaml\n' > "$gi"
  fi
}

# --- value parsing -----------------------------------------------------------

# _yaml_val <raw-after-colon> — trim surrounding whitespace and double quotes.
_yaml_val() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"   # strip leading whitespace
  v="${v%"${v##*[![:space:]]}"}"   # strip trailing whitespace
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
  esac
  printf '%s' "$v"
}

# _in_list_sp <space-list> <value> — membership test for a space-separated list.
_in_list_sp() {
  case " $1 " in
    *" $2 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- pins: read --------------------------------------------------------------

# config_read_pins — emit one record per pinned entry:
#   skill<TAB>tools<TAB>scope<TAB>path
config_read_pins() {
  [ -f "$CONFIG_FILE" ] || return 0
  local in=0 line
  local f_skill="" f_tools="" f_scope="" f_path="" have=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      pins:*) in=1; continue ;;
    esac
    [ "$in" -eq 1 ] || continue
    case "$line" in
      ' '*) : ;;            # indented → inside the pins block
      '')   continue ;;     # blank line → ignore
      *)                    # a new top-level key → block ended
        [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\n' "$f_skill" "$f_tools" "$f_scope" "$f_path"
        have=0; in=0; continue ;;
    esac
    case "$line" in
      *-\ skill:*)
        [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\n' "$f_skill" "$f_tools" "$f_scope" "$f_path"
        f_skill="$(_yaml_val "${line#*skill:}")"; f_tools=""; f_scope=""; f_path=""; have=1 ;;
      *tools:*) f_tools="$(_yaml_val "${line#*tools:}")" ;;
      *scope:*) f_scope="$(_yaml_val "${line#*scope:}")" ;;
      *path:*)  f_path="$(_yaml_val "${line#*path:}")" ;;
    esac
  done < "$CONFIG_FILE"
  [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\n' "$f_skill" "$f_tools" "$f_scope" "$f_path"
  return 0
}

# --- pins: write -------------------------------------------------------------

# _write_pins_block <records> — print the YAML pins: block for the given records.
_write_pins_block() {
  local records="$1"
  printf 'pins:\n'
  [ -n "$records" ] || return 0
  local OLDIFS="$IFS"; IFS='
'
  local r
  for r in $records; do
    IFS="$OLDIFS"
    local skill tools scope path rest
    skill="${r%%"$_SEP"*}"; rest="${r#*"$_SEP"}"
    tools="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    scope="${rest%%"$_SEP"*}"; path="${rest#*"$_SEP"}"
    printf '  - skill: %s\n' "$skill"
    printf '    tools: %s\n' "$tools"
    printf '    scope: %s\n' "$scope"
    if [ -n "$path" ]; then
      printf '    path: %s\n' "$path"
    else
      printf '    path: ""\n'
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
}

# config_write_pins <records> — splice the pins: block back into config.yaml,
# preserving every other (current or future) top-level section.
config_write_pins() {
  local records="$1"
  local tmp; tmp="$(mktemp)"
  local in=0 done_block=0 line
  if [ -f "$CONFIG_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$in" -eq 1 ]; then
        case "$line" in
          ' '*|'') continue ;;   # still inside the old pins block → drop
          *) in=0 ;;             # new top-level key → block ended, fall through
        esac
      fi
      case "$line" in
        pins:*)
          _write_pins_block "$records" >> "$tmp"
          in=1; done_block=1; continue ;;
      esac
      printf '%s\n' "$line" >> "$tmp"
    done < "$CONFIG_FILE"
  fi
  if [ "$done_block" -eq 0 ]; then
    printf '\n' >> "$tmp"
    _write_pins_block "$records" >> "$tmp"
  fi
  mv "$tmp" "$CONFIG_FILE"
}

# --- pins: mutate ------------------------------------------------------------

# config_add_pin <skill> <tools> <scope> <path>
# Merge tools into the existing (skill,scope,path) record, else append a new one.
config_add_pin() {
  local skill="$1" tools="$2" scope="$3" path="$4"
  local out="" found=0 r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_pins); do
    IFS="$OLDIFS"
    local rs rt rsc rp rest
    rs="${r%%"$_SEP"*}"; rest="${r#*"$_SEP"}"
    rt="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    rsc="${rest%%"$_SEP"*}"; rp="${rest#*"$_SEP"}"
    if [ "$rs" = "$skill" ] && [ "$rsc" = "$scope" ] && [ "$rp" = "$path" ]; then
      local t
      for t in $tools; do
        _in_list_sp "$rt" "$t" || rt="${rt:+$rt }$t"
      done
      found=1
      out="${out:+$out
}$rs$_SEP$rt$_SEP$rsc$_SEP$rp"
    else
      out="${out:+$out
}$r"
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
  if [ "$found" -eq 0 ]; then
    out="${out:+$out
}$skill$_SEP$tools$_SEP$scope$_SEP$path"
  fi
  config_write_pins "$out"
}

# config_remove_pin <skill> <scope> <path> <tools-or-empty>
# Drop the named tools from the matching record (whole record if tools empty or
# nothing remains).
config_remove_pin() {
  local skill="$1" scope="$2" path="$3" rmtools="$4"
  local out="" r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_pins); do
    IFS="$OLDIFS"
    local rs rt rsc rp rest
    rs="${r%%"$_SEP"*}"; rest="${r#*"$_SEP"}"
    rt="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    rsc="${rest%%"$_SEP"*}"; rp="${rest#*"$_SEP"}"
    if [ "$rs" = "$skill" ] && [ "$rsc" = "$scope" ] && [ "$rp" = "$path" ]; then
      if [ -n "$rmtools" ]; then
        local newt="" t
        for t in $rt; do
          _in_list_sp "$rmtools" "$t" || newt="${newt:+$newt }$t"
        done
        if [ -n "$newt" ]; then
          out="${out:+$out
}$rs$_SEP$newt$_SEP$rsc$_SEP$rp"
        fi
      fi
      # tools empty, or all tools removed → record dropped entirely
    else
      out="${out:+$out
}$r"
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
  config_write_pins "$out"
}

# config_remove_pins_matching <selector> — drop every pin record whose skill is
# covered by <selector>. "Category/skill" matches that exact skill; "Category"
# matches the category pin and every "Category/<skill>" pin. Returns 0 if any
# record was removed (so callers can report it), 1 otherwise.
config_remove_pins_matching() {
  local sel="$1" out="" dropped=0 r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_pins); do
    IFS="$OLDIFS"
    local rs="${r%%"$_SEP"*}" drop=0
    case "$sel" in
      */*) [ "$rs" = "$sel" ] && drop=1 ;;
      *)
        [ "$rs" = "$sel" ] && drop=1
        case "$rs" in "$sel"/*) drop=1 ;; esac
        ;;
    esac
    if [ "$drop" -eq 1 ]; then
      dropped=1
    else
      out="${out:+$out
}$r"
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
  [ "$dropped" -eq 1 ] || return 1
  config_write_pins "$out"
  return 0
}

# config_is_pinned <skill> <scope> <path> — 0 if a matching record exists.
config_is_pinned() {
  local skill="$1" scope="$2" path="$3" r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_pins); do
    IFS="$OLDIFS"
    local rs rsc rp rest
    rs="${r%%"$_SEP"*}"; rest="${r#*"$_SEP"}"
    rest="${rest#*"$_SEP"}"        # drop tools
    rsc="${rest%%"$_SEP"*}"; rp="${rest#*"$_SEP"}"
    if [ "$rs" = "$skill" ] && [ "$rsc" = "$scope" ] && [ "$rp" = "$path" ]; then
      IFS="$OLDIFS"; return 0
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
  return 1
}

# _record_dir_for_tool <tool> <scope> <project-root>
# Resolve the destination skills dir for a tool given a pin's scope/path.
_record_dir_for_tool() {
  if [ "$2" = "global" ]; then
    global_dir_for_tool "$1"
  else
    project_dir_for_tool "$1" "$3"
  fi
}
