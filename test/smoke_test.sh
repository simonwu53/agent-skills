#!/usr/bin/env bash
# Offline smoke test for main.sh. Runs against a scratch copy of the manager
# (main.sh + src/) in a temp dir, so the real repo, its submodules, and the
# real config.yaml are never touched. "GitHub" loads are exercised through
# local fixture git repos, mapped to fake github.com URLs with url.insteadOf.
# Run from anywhere:  bash test/smoke_test.sh
set -euo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Scratch manager repo (REPO_ROOT for every main.sh run below).
MGR="$WORK/manager"
mkdir -p "$MGR"
cp "$SRC_ROOT/main.sh" "$MGR/"
cp -R "$SRC_ROOT/src" "$MGR/"
git -C "$MGR" init -q

# git config via environment: allow file-protocol submodules, give an identity,
# and rewrite the fake github URLs to the local fixture repos.
export GIT_CONFIG_COUNT=6
export GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
export GIT_CONFIG_KEY_1=user.name          GIT_CONFIG_VALUE_1=smoke
export GIT_CONFIG_KEY_2=user.email         GIT_CONFIG_VALUE_2=smoke@test
export GIT_CONFIG_KEY_3="url.file://$WORK/fixrepo.insteadOf"   GIT_CONFIG_VALUE_3=https://github.com/tauthor/fixrepo
export GIT_CONFIG_KEY_4="url.file://$WORK/rootrepo.insteadOf"  GIT_CONFIG_VALUE_4=https://github.com/tauthor/rootrepo
export GIT_CONFIG_KEY_5="url.file://$WORK/clashrepo.insteadOf" GIT_CONFIG_VALUE_5=https://github.com/oauthor/clashrepo

CONFIG="$MGR/config.yaml"

pass=0; fail=0
check() { # check <desc> <test-cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then printf 'ok   - %s\n' "$desc"; pass=$((pass+1))
  else printf 'FAIL - %s\n' "$desc"; fail=$((fail+1)); fi
}
in_file()     { grep -q -e "$1" "$2"; }
not_in_file() { ! grep -q -e "$1" "$2"; }
not()         { ! "$@"; }
is_installed() { [ -L "$1" ] || [ -f "$1/SKILL.md" ]; }
# skill_block <name> — print the config.yaml block of one skill entry.
skill_block() {
  awk -v n="  - name: $1" '
    $0 == n            { f=1; print; next }
    f && /^  - name: / { f=0 }
    f && /^[^ ]/       { f=0 }
    f                  { print }' "$CONFIG"
}
block_has()     { skill_block "$1" | grep -q -e "$2"; }
block_has_not() { ! block_has "$1" "$2"; }

mk_skill() { # mk_skill <dir> <name>
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: test skill %s\n---\nhello\n' "$2" "$2" > "$1/SKILL.md"
}
mk_gitrepo() { # mk_gitrepo <dir>
  git -C "$1" init -q
  git -C "$1" add -A
  git -C "$1" commit -qm fixture
}

# --- fixtures ----------------------------------------------------------------
mk_skill "$WORK/src/alpha" alpha
printf 'echo hi\n' > "$WORK/src/alpha/scripts.sh"

mkdir -p "$WORK/zipsrc/beta"
mk_skill "$WORK/zipsrc/beta" beta
( cd "$WORK/zipsrc" && zip -qr "$WORK/beta.zip" beta )

# fixrepo: flat skills + a nested category + a non-skill dir
mk_skill "$WORK/fixrepo/skills/gamma" gamma
mk_skill "$WORK/fixrepo/skills/epsilon" epsilon
mk_skill "$WORK/fixrepo/skills/Cat1/delta" delta
mkdir -p "$WORK/fixrepo/skills/notaskill"; touch "$WORK/fixrepo/skills/notaskill/README.md"
mk_gitrepo "$WORK/fixrepo"

# rootrepo: the repo root is itself a skill
mk_skill "$WORK/rootrepo" rootrepo
mk_gitrepo "$WORK/rootrepo"

# clashrepo: provides another "gamma"
mk_skill "$WORK/clashrepo/skills/gamma" gamma
mk_gitrepo "$WORK/clashrepo"

PROJ="$WORK/project"; mkdir -p "$PROJ"
run() { "$MGR/main.sh" "$@"; }

# --- load: local path & zip --------------------------------------------------
run --load -p "$WORK/src/alpha" --cat CatL >/dev/null
check "load --path stores under skills/local"  test -f "$MGR/skills/local/alpha/SKILL.md"
check "load --path keeps extra files"          test -f "$MGR/skills/local/alpha/scripts.sh"
check "config: local entry for alpha"          in_file "  - name: alpha" "$CONFIG"
check "config: alpha skill repo=local"         block_has alpha "repo: local"
check "config: alpha category recorded"        block_has alpha "category: CatL"

run --load -f "$WORK/beta.zip" --cat CatL >/dev/null
check "load --file stores under skills/local"  test -f "$MGR/skills/local/beta/SKILL.md"

# --- load: github auto mode (flat skills/, batch confirm) --------------------
printf 'y\n' | run --load --link https://github.com/tauthor/fixrepo --cat CatA >/dev/null
check "submodule checkout exists"     test -f "$MGR/skills/repository/tauthor-fixrepo/skills/gamma/SKILL.md"
check ".gitmodules records the repo"  in_file "tauthor/fixrepo" "$MGR/.gitmodules"
check "config: repo entry added"      in_file "author: tauthor" "$CONFIG"
check "config: gamma registered"      block_has gamma "repo: tauthor/fixrepo"
check "config: epsilon registered"    block_has epsilon "subpath: skills/epsilon"
check "config: category from --cat"   block_has gamma "category: CatA"
check "non-skill dir not registered"  not_in_file "notaskill" "$CONFIG"
check "nested category dir skipped in auto mode" block_has_not delta "repo:"

# --- load: --skill Cat/name infers the category ------------------------------
run --load --link https://github.com/tauthor/fixrepo --skill Cat1/delta >/dev/null
check "config: delta registered"          block_has delta "subpath: skills/Cat1/delta"
check "config: delta category inferred"   block_has delta "category: Cat1"

# --- load: repo root is a skill ----------------------------------------------
run --load --link https://github.com/tauthor/rootrepo --cat CatA >/dev/null
check "root-skill repo registered"       block_has rootrepo "repo: tauthor/rootrepo"
check "root-skill subpath is empty"      block_has rootrepo 'subpath: ""'

# --- load: /tree/ links are rejected -----------------------------------------
check "subfolder link rejected" \
  not run --load --link https://github.com/o/r/tree/main/skills/x

# --- load: name clash → keep old / replace -----------------------------------
printf 'n\n' | run --load --link https://github.com/oauthor/clashrepo >/dev/null 2>&1 || true
check "clash declined keeps old source"    block_has gamma "repo: tauthor/fixrepo"
check "useless submodule cleaned up again" test ! -d "$MGR/skills/repository/oauthor-clashrepo"

printf 'y\ny\n' | run --load --link https://github.com/oauthor/clashrepo >/dev/null
check "clash accepted replaces source"     block_has gamma "repo: oauthor/clashrepo"
check "replacement did not dup the entry"  test "$(grep -c '  - name: gamma' "$CONFIG")" = 1

# --- install: project scope, copy by default ---------------------------------
run --install --skill alpha --claude -p "$PROJ" >/dev/null
check "install copies the skill"            test -f "$PROJ/.claude/skills/alpha/SKILL.md"
check "default install is a copy, not link" test ! -L "$PROJ/.claude/skills/alpha"
check "config: project recorded on alpha"   block_has alpha "- $PROJ"

# --- install: a category selector installs every skill in it -----------------
printf 'y\n' | run --install --skill CatA --claude -p "$PROJ" >/dev/null
check "category install: epsilon present"  is_installed "$PROJ/.claude/skills/epsilon"
check "category install: rootrepo present" is_installed "$PROJ/.claude/skills/rootrepo"
check "root-skill copy drops .git pointer" test ! -e "$PROJ/.claude/skills/rootrepo/.git"

# --- install: --symlink opts into soft links ---------------------------------
printf 'y\n' | run --install --skill alpha --claude -p "$PROJ" --symlink >/dev/null
check "--symlink creates a symlink"        test -L "$PROJ/.claude/skills/alpha"

# --- pin: flag set + installed now -------------------------------------------
run --pin --skill beta --claude -p "$PROJ" >/dev/null
check "pin installs the skill"   is_installed "$PROJ/.claude/skills/beta"
check "config: pinned flag set"  block_has beta "pinned: true"

# --- pin survives an install-clear -------------------------------------------
printf 'y\ny\n' | run --install --skill alpha --claude -p "$PROJ" >/dev/null
check "clear happened (epsilon gone)"      test ! -e "$PROJ/.claude/skills/epsilon"
check "pinned skill re-installed on clear" is_installed "$PROJ/.claude/skills/beta"
check "requested skill installed"          is_installed "$PROJ/.claude/skills/alpha"

# --- update: overwrites without prompting ------------------------------------
run --update --skill alpha --claude -p "$PROJ" >/dev/null
check "--update reinstalls in place"       is_installed "$PROJ/.claude/skills/alpha"

# --- remove: named skill + install-state cleanup -----------------------------
printf 'y\n' | run --remove --skill alpha --claude -p "$PROJ" >/dev/null
check "remove deletes the skill"           test ! -e "$PROJ/.claude/skills/alpha"
check "config: project record dropped"     block_has_not alpha "- $PROJ"

# --- remove: pinned skill warns and unpins -----------------------------------
printf 'y\n' | run --remove --skill beta --claude -p "$PROJ" >/dev/null
check "pinned skill removed"               test ! -e "$PROJ/.claude/skills/beta"
check "config: pin flag cleared"           block_has beta "pinned: false"

# --- list --------------------------------------------------------------------
check "list shows library category" bash -c "'$MGR/main.sh' --list | grep -q 'CatA/'"
check "list shows source repo slug" bash -c "'$MGR/main.sh' --list | grep -q 'tauthor/fixrepo'"

# --- unload: last skill of a repo removes the submodule ----------------------
printf 'y\ny\n' | run --unload --skill gamma >/dev/null
check "unload drops the db entry"          block_has_not gamma "repo:"
check "unload removes emptied submodule"   test ! -d "$MGR/skills/repository/oauthor-clashrepo"
check "other repos untouched"              test -d "$MGR/skills/repository/tauthor-fixrepo"

# --- unload: local skill deletes its source ----------------------------------
printf 'y\n' | run --unload --skill alpha >/dev/null
check "local source deleted"     test ! -d "$MGR/skills/local/alpha"
check "local db entry deleted"   block_has_not alpha "repo:"

# --- summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
