#!/usr/bin/env bash
# config.sh — machine-local configuration (config.yaml) for the skills manager.
# Sourced by common.sh. Bash 3.2 / Zsh compatible. Pure-bash YAML handling for a
# deliberately constrained schema (see README). Schema v2 is the library
# database: loaded repos (git submodules), local sources, and skills with their
# category, pin flag, and install state.

# Config file path. Overridable via the CONFIG_FILE env var (used by tests).
CONFIG_FILE="${CONFIG_FILE:-$REPO_ROOT/config.yaml}"

# Field separator for the record formats emitted by the readers (one record per
# line). The projects list is packed into a single field with _PSEP.
_SEP=$'\t'
_PSEP=$'\x1f'

# Record layouts:
#   repos:  slug<SEP>url<SEP>path<SEP>lastUpdate<SEP>dateAdded   (slug = author/name)
#   local:  name<SEP>path<SEP>source<SEP>dateAdded
#   skills: name<SEP>repo<SEP>subpath<SEP>category<SEP>pinned<SEP>agents<SEP>projects

_config_now() { date '+%F %T'; }

# --- init --------------------------------------------------------------------

# init_config — create a v2 config.yaml if missing; back up and re-init a v1
# file; make sure the default config.yaml is git-ignored.
init_config() {
  if [ -f "$CONFIG_FILE" ]; then
    if grep -q '^version: 1' "$CONFIG_FILE" 2>/dev/null; then
      mv "$CONFIG_FILE" "$CONFIG_FILE.v1.bak"
      warn "config.yaml was schema v1; backed up to $(basename "$CONFIG_FILE").v1.bak and re-initialized as v2."
      _write_empty_config
    fi
  else
    _write_empty_config
  fi
  _ensure_gitignore_config
}

_write_empty_config() {
  cat > "$CONFIG_FILE" <<'EOF'
# 533s-skills configuration — machine-local, not version controlled.
# Managed by main.sh. Keep the structure if editing by hand.
version: 2

repos:

local:

skills:
EOF
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
    "[]")  v="" ;;
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

# --- section readers ---------------------------------------------------------
# All three walk the file with the same line rules: a top-level `<section>:`
# opens the block, indented lines belong to it, the next top-level key ends it.
# `- name:` starts a new item.

# config_read_repos — slug<SEP>url<SEP>path<SEP>lastUpdate<SEP>dateAdded
config_read_repos() {
  [ -f "$CONFIG_FILE" ] || return 0
  local in=0 line
  local f_name="" f_author="" f_url="" f_path="" f_lu="" f_da="" have=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      repos:*) in=1; continue ;;
    esac
    [ "$in" -eq 1 ] || continue
    case "$line" in
      ' '*) : ;;
      '')   continue ;;
      *)
        [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\t%s\n' "$f_author/$f_name" "$f_url" "$f_path" "$f_lu" "$f_da"
        have=0; in=0; continue ;;
    esac
    case "$line" in
      *-\ name:*)
        [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\t%s\n' "$f_author/$f_name" "$f_url" "$f_path" "$f_lu" "$f_da"
        f_name="$(_yaml_val "${line#*name:}")"; f_author=""; f_url=""; f_path=""; f_lu=""; f_da=""; have=1 ;;
      *author:*)     f_author="$(_yaml_val "${line#*author:}")" ;;
      *url:*)        f_url="$(_yaml_val "${line#*url:}")" ;;
      *lastUpdate:*) f_lu="$(_yaml_val "${line#*lastUpdate:}")" ;;
      *dateAdded:*)  f_da="$(_yaml_val "${line#*dateAdded:}")" ;;
      *path:*)       f_path="$(_yaml_val "${line#*path:}")" ;;
    esac
  done < "$CONFIG_FILE"
  [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\t%s\n' "$f_author/$f_name" "$f_url" "$f_path" "$f_lu" "$f_da"
  return 0
}

# config_read_local — name<SEP>path<SEP>source<SEP>dateAdded
config_read_local() {
  [ -f "$CONFIG_FILE" ] || return 0
  local in=0 line
  local f_name="" f_path="" f_src="" f_da="" have=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      local:*) in=1; continue ;;
    esac
    [ "$in" -eq 1 ] || continue
    case "$line" in
      ' '*) : ;;
      '')   continue ;;
      *)
        [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\n' "$f_name" "$f_path" "$f_src" "$f_da"
        have=0; in=0; continue ;;
    esac
    case "$line" in
      *-\ name:*)
        [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\n' "$f_name" "$f_path" "$f_src" "$f_da"
        f_name="$(_yaml_val "${line#*name:}")"; f_path=""; f_src=""; f_da=""; have=1 ;;
      *source:*)    f_src="$(_yaml_val "${line#*source:}")" ;;
      *dateAdded:*) f_da="$(_yaml_val "${line#*dateAdded:}")" ;;
      *path:*)      f_path="$(_yaml_val "${line#*path:}")" ;;
    esac
  done < "$CONFIG_FILE"
  [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\n' "$f_name" "$f_path" "$f_src" "$f_da"
  return 0
}

# config_read_skills — name<SEP>repo<SEP>subpath<SEP>category<SEP>pinned<SEP>agents<SEP>projects
config_read_skills() {
  [ -f "$CONFIG_FILE" ] || return 0
  local in=0 inproj=0 line
  local f_name="" f_repo="" f_sub="" f_cat="" f_pin="" f_ag="" f_pr="" have=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      skills:*) in=1; continue ;;
    esac
    [ "$in" -eq 1 ] || continue
    case "$line" in
      ' '*) : ;;
      '')   continue ;;
      *)
        [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f_name" "$f_repo" "$f_sub" "$f_cat" "$f_pin" "$f_ag" "$f_pr"
        have=0; in=0; inproj=0; continue ;;
    esac
    case "$line" in
      *-\ name:*)
        [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f_name" "$f_repo" "$f_sub" "$f_cat" "$f_pin" "$f_ag" "$f_pr"
        f_name="$(_yaml_val "${line#*name:}")"; f_repo=""; f_sub=""; f_cat=""; f_pin=""; f_ag=""; f_pr=""
        have=1; inproj=0 ;;
      *projects:*) inproj=1 ;;
      *repo:*)     f_repo="$(_yaml_val "${line#*repo:}")"; inproj=0 ;;
      *subpath:*)  f_sub="$(_yaml_val "${line#*subpath:}")"; inproj=0 ;;
      *category:*) f_cat="$(_yaml_val "${line#*category:}")"; inproj=0 ;;
      *pinned:*)   f_pin="$(_yaml_val "${line#*pinned:}")"; inproj=0 ;;
      *agents:*)   f_ag="$(_yaml_val "${line#*agents:}")"; inproj=0 ;;
      *-\ *)
        if [ "$inproj" -eq 1 ]; then
          local pv; pv="$(_yaml_val "${line#*- }")"
          f_pr="${f_pr:+$f_pr$_PSEP}$pv"
        fi ;;
    esac
  done < "$CONFIG_FILE"
  [ "$have" -eq 1 ] && printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f_name" "$f_repo" "$f_sub" "$f_cat" "$f_pin" "$f_ag" "$f_pr"
  return 0
}

# --- section writers ---------------------------------------------------------

# _q <value> — quote a value for YAML output ("" when empty).
_q() {
  if [ -n "$1" ]; then printf '%s' "$1"; else printf '""'; fi
}

# _render_repos_block <records>
_render_repos_block() {
  printf 'repos:\n'
  [ -n "$1" ] || return 0
  local OLDIFS="$IFS" r; IFS='
'
  for r in $1; do
    IFS="$OLDIFS"
    local slug url path lu da rest
    slug="${r%%"$_SEP"*}"; rest="${r#*"$_SEP"}"
    url="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    path="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    lu="${rest%%"$_SEP"*}"; da="${rest#*"$_SEP"}"
    printf '  - name: %s\n'       "${slug#*/}"
    printf '    author: %s\n'     "${slug%%/*}"
    printf '    url: %s\n'        "$(_q "$url")"
    printf '    path: %s\n'       "$path"
    printf '    lastUpdate: %s\n' "$lu"
    printf '    dateAdded: %s\n'  "$da"
    IFS='
'
  done
  IFS="$OLDIFS"
}

# _render_local_block <records>
_render_local_block() {
  printf 'local:\n'
  [ -n "$1" ] || return 0
  local OLDIFS="$IFS" r; IFS='
'
  for r in $1; do
    IFS="$OLDIFS"
    local name path src da rest
    name="${r%%"$_SEP"*}"; rest="${r#*"$_SEP"}"
    path="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    src="${rest%%"$_SEP"*}"; da="${rest#*"$_SEP"}"
    printf '  - name: %s\n'      "$name"
    printf '    path: %s\n'      "$path"
    printf '    source: %s\n'    "$(_q "$src")"
    printf '    dateAdded: %s\n' "$da"
    IFS='
'
  done
  IFS="$OLDIFS"
}

# _render_skills_block <records>
_render_skills_block() {
  printf 'skills:\n'
  [ -n "$1" ] || return 0
  local OLDIFS="$IFS" r; IFS='
'
  for r in $1; do
    IFS="$OLDIFS"
    local name repo sub cat pin ag pr rest
    name="${r%%"$_SEP"*}"; rest="${r#*"$_SEP"}"
    repo="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    sub="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    cat="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    pin="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
    ag="${rest%%"$_SEP"*}"; pr="${rest#*"$_SEP"}"
    printf '  - name: %s\n'     "$name"
    printf '    repo: %s\n'     "$repo"
    printf '    subpath: %s\n'  "$(_q "$sub")"
    printf '    category: %s\n' "$cat"
    printf '    pinned: %s\n'   "${pin:-false}"
    printf '    agents: %s\n'   "$(_q "$ag")"
    if [ -n "$pr" ]; then
      printf '    projects:\n'
      local p IFS2="$IFS"; IFS="$_PSEP"
      for p in $pr; do printf '      - %s\n' "$p"; done
      IFS="$IFS2"
    else
      printf '    projects: []\n'
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
}

# _config_write_section <section> <records> — splice the section block back into
# config.yaml, preserving every other (current or future) top-level section.
_config_write_section() {
  local section="$1" records="$2"
  local tmp; tmp="$(mktemp)"
  local in=0 done_block=0 line
  if [ -f "$CONFIG_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$in" -eq 1 ]; then
        case "$line" in
          ' '*|'') continue ;;   # still inside the old block → drop
          *) in=0 ;;             # new top-level key → block ended, fall through
        esac
      fi
      case "$line" in
        "$section":*)
          case "$section" in
            repos)  _render_repos_block  "$records" >> "$tmp" ;;
            local)  _render_local_block  "$records" >> "$tmp" ;;
            skills) _render_skills_block "$records" >> "$tmp" ;;
          esac
          printf '\n' >> "$tmp"
          in=1; done_block=1; continue ;;
      esac
      printf '%s\n' "$line" >> "$tmp"
    done < "$CONFIG_FILE"
  fi
  if [ "$done_block" -eq 0 ]; then
    printf '\n' >> "$tmp"
    case "$section" in
      repos)  _render_repos_block  "$records" >> "$tmp" ;;
      local)  _render_local_block  "$records" >> "$tmp" ;;
      skills) _render_skills_block "$records" >> "$tmp" ;;
    esac
  fi
  mv "$tmp" "$CONFIG_FILE"
}

# --- repos -------------------------------------------------------------------

# config_repo_record <slug> — print the matching record, or fail.
config_repo_record() {
  local slug="$1" r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_repos); do
    IFS="$OLDIFS"
    if [ "${r%%"$_SEP"*}" = "$slug" ]; then printf '%s\n' "$r"; return 0; fi
    IFS='
'
  done
  IFS="$OLDIFS"
  return 1
}

# config_repo_path <slug> — print the repo's path (relative to repo root).
config_repo_path() {
  local r; r="$(config_repo_record "$1")" || return 1
  local rest="${r#*"$_SEP"}"; rest="${rest#*"$_SEP"}"
  printf '%s\n' "${rest%%"$_SEP"*}"
}

# config_add_repo <author> <name> <url> <path> — append if the slug is new.
config_add_repo() {
  local author="$1" name="$2" url="$3" path="$4"
  config_repo_record "$author/$name" >/dev/null && return 0
  local now; now="$(_config_now)"
  local out; out="$(config_read_repos)"
  out="${out:+$out
}$author/$name$_SEP$url$_SEP$path$_SEP$now$_SEP$now"
  _config_write_section repos "$out"
}

# config_remove_repo <slug>
config_remove_repo() {
  local slug="$1" out="" r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_repos); do
    IFS="$OLDIFS"
    [ "${r%%"$_SEP"*}" = "$slug" ] || out="${out:+$out
}$r"
    IFS='
'
  done
  IFS="$OLDIFS"
  _config_write_section repos "$out"
}

# --- local sources -----------------------------------------------------------

config_local_record() {
  local name="$1" r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_local); do
    IFS="$OLDIFS"
    if [ "${r%%"$_SEP"*}" = "$name" ]; then printf '%s\n' "$r"; return 0; fi
    IFS='
'
  done
  IFS="$OLDIFS"
  return 1
}

# config_add_local <name> <path> <source> — append or refresh by name.
config_add_local() {
  local name="$1" path="$2" src="$3"
  local now; now="$(_config_now)"
  local out="" r found=0
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_local); do
    IFS="$OLDIFS"
    if [ "${r%%"$_SEP"*}" = "$name" ]; then
      out="${out:+$out
}$name$_SEP$path$_SEP$src$_SEP$now"; found=1
    else
      out="${out:+$out
}$r"
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
  [ "$found" -eq 1 ] || out="${out:+$out
}$name$_SEP$path$_SEP$src$_SEP$now"
  _config_write_section local "$out"
}

# config_remove_local <name>
config_remove_local() {
  local name="$1" out="" r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_local); do
    IFS="$OLDIFS"
    [ "${r%%"$_SEP"*}" = "$name" ] || out="${out:+$out
}$r"
    IFS='
'
  done
  IFS="$OLDIFS"
  _config_write_section local "$out"
}

# --- skills ------------------------------------------------------------------

# config_get_skill <name> — print the matching record, or fail.
config_get_skill() {
  local name="$1" r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_skills); do
    IFS="$OLDIFS"
    if [ "${r%%"$_SEP"*}" = "$name" ]; then printf '%s\n' "$r"; return 0; fi
    IFS='
'
  done
  IFS="$OLDIFS"
  return 1
}

config_skill_exists() { config_get_skill "$1" >/dev/null; }

# config_add_skill <name> <repo-slug-or-local> <subpath> <category>
# Appends a fresh entry (pinned false, no install state); replaces an existing
# entry of the same name (callers are responsible for the collision policy).
config_add_skill() {
  local name="$1" repo="$2" sub="$3" cat="$4"
  local out="" r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_skills); do
    IFS="$OLDIFS"
    [ "${r%%"$_SEP"*}" = "$name" ] || out="${out:+$out
}$r"
    IFS='
'
  done
  IFS="$OLDIFS"
  out="${out:+$out
}$name$_SEP$repo$_SEP$sub$_SEP$cat${_SEP}false$_SEP$_SEP"
  _config_write_section skills "$out"
}

# config_remove_skill <name>
config_remove_skill() {
  local name="$1" out="" r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_skills); do
    IFS="$OLDIFS"
    [ "${r%%"$_SEP"*}" = "$name" ] || out="${out:+$out
}$r"
    IFS='
'
  done
  IFS="$OLDIFS"
  _config_write_section skills "$out"
}

# config_set_skill_field <name> <field> <value>
# field: repo | subpath | category | pinned | agents | projects
# (projects value is the packed _PSEP-joined list)
config_set_skill_field() {
  local name="$1" field="$2" value="$3"
  local out="" r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_skills); do
    IFS="$OLDIFS"
    if [ "${r%%"$_SEP"*}" = "$name" ]; then
      local f_repo f_sub f_cat f_pin f_ag f_pr rest
      rest="${r#*"$_SEP"}"
      f_repo="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
      f_sub="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
      f_cat="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
      f_pin="${rest%%"$_SEP"*}"; rest="${rest#*"$_SEP"}"
      f_ag="${rest%%"$_SEP"*}"; f_pr="${rest#*"$_SEP"}"
      case "$field" in
        repo)     f_repo="$value" ;;
        subpath)  f_sub="$value" ;;
        category) f_cat="$value" ;;
        pinned)   f_pin="$value" ;;
        agents)   f_ag="$value" ;;
        projects) f_pr="$value" ;;
      esac
      out="${out:+$out
}$name$_SEP$f_repo$_SEP$f_sub$_SEP$f_cat$_SEP$f_pin$_SEP$f_ag$_SEP$f_pr"
    else
      out="${out:+$out
}$r"
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
  _config_write_section skills "$out"
}

# _skill_field <record> <index> — print field N (1-based) of a skills record.
_skill_field() {
  local r="$1" i="$2"
  while [ "$i" -gt 1 ]; do r="${r#*"$_SEP"}"; i=$((i - 1)); done
  case "$i" in
    7) printf '%s\n' "$r" ;;
    *) printf '%s\n' "${r%%"$_SEP"*}" ;;
  esac
}

# config_skill_dir <name> — print the absolute skill source directory.
config_skill_dir() {
  local r; r="$(config_get_skill "$1")" || return 1
  local repo sub
  repo="$(_skill_field "$r" 2)"
  sub="$(_skill_field "$r" 3)"
  if [ "$repo" = "local" ]; then
    local lr; lr="$(config_local_record "$1")" || return 1
    local rest="${lr#*"$_SEP"}"
    printf '%s\n' "$REPO_ROOT/${rest%%"$_SEP"*}"
  else
    local rpath; rpath="$(config_repo_path "$repo")" || return 1
    if [ -n "$sub" ]; then
      printf '%s\n' "$REPO_ROOT/$rpath/$sub"
    else
      printf '%s\n' "$REPO_ROOT/$rpath"
    fi
  fi
}

# config_skills_in_category <category> — print matching skill names.
config_skills_in_category() {
  local cat="$1" r found=1
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_skills); do
    IFS="$OLDIFS"
    if [ "$(_skill_field "$r" 4)" = "$cat" ]; then
      printf '%s\n' "${r%%"$_SEP"*}"; found=0
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
  return "$found"
}

# config_skills_in_repo <slug> — print names of skills sourced from the repo.
config_skills_in_repo() {
  local slug="$1" r found=1
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_skills); do
    IFS="$OLDIFS"
    if [ "$(_skill_field "$r" 2)" = "$slug" ]; then
      printf '%s\n' "${r%%"$_SEP"*}"; found=0
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
  return "$found"
}

# config_skill_is_pinned <name>
config_skill_is_pinned() {
  local r; r="$(config_get_skill "$1")" || return 1
  [ "$(_skill_field "$r" 5)" = "true" ]
}

# config_pinned_skills — print the names of every pinned skill.
config_pinned_skills() {
  local r
  local OLDIFS="$IFS"; IFS='
'
  for r in $(config_read_skills); do
    IFS="$OLDIFS"
    [ "$(_skill_field "$r" 5)" = "true" ] && printf '%s\n' "${r%%"$_SEP"*}"
    IFS='
'
  done
  IFS="$OLDIFS"
  return 0
}

# --- install-state helpers ---------------------------------------------------

# config_skill_add_agent <name> <tool> / config_skill_remove_agent <name> <tool>
config_skill_add_agent() {
  local r; r="$(config_get_skill "$1")" || return 1
  local ag; ag="$(_skill_field "$r" 6)"
  _in_list_sp "$ag" "$2" && return 0
  config_set_skill_field "$1" agents "${ag:+$ag }$2"
}

config_skill_remove_agent() {
  local r; r="$(config_get_skill "$1")" || return 1
  local ag t new=""
  ag="$(_skill_field "$r" 6)"
  for t in $ag; do
    [ "$t" = "$2" ] || new="${new:+$new }$t"
  done
  [ "$new" = "$ag" ] || config_set_skill_field "$1" agents "$new"
}

# config_skill_add_project <name> <abs-path> / config_skill_remove_project ...
config_skill_add_project() {
  local r; r="$(config_get_skill "$1")" || return 1
  local pr; pr="$(_skill_field "$r" 7)"
  case "$_PSEP$pr$_PSEP" in
    *"$_PSEP$2$_PSEP"*) return 0 ;;
  esac
  config_set_skill_field "$1" projects "${pr:+$pr$_PSEP}$2"
}

config_skill_remove_project() {
  local r; r="$(config_get_skill "$1")" || return 1
  local pr p new=""
  pr="$(_skill_field "$r" 7)"
  local OLDIFS="$IFS"; IFS="$_PSEP"
  for p in $pr; do
    IFS="$OLDIFS"
    [ "$p" = "$2" ] || new="${new:+$new$_PSEP}$p"
    IFS="$_PSEP"
  done
  IFS="$OLDIFS"
  [ "$new" = "$pr" ] || config_set_skill_field "$1" projects "$new"
}
