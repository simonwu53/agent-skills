#!/usr/bin/env bash
# Offline smoke test for main.sh. Touches only temp dirs and skills/_SmokeTest.
# Run from anywhere:  bash test/smoke_test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_ROOT"

WORK="$(mktemp -d)"
CATEGORY="_SmokeTest"
trap 'rm -rf "$WORK"; rm -rf "skills/$CATEGORY"' EXIT

pass=0; fail=0
check() { # check <desc> <test-cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then printf 'ok   - %s\n' "$desc"; pass=$((pass+1))
  else printf 'FAIL - %s\n' "$desc"; fail=$((fail+1)); fi
}

# --- fixtures ---------------------------------------------------------------
mkdir -p "$WORK/src/alpha/scripts"
printf -- '---\nname: alpha\ndescription: test skill alpha\n---\nhello\n' > "$WORK/src/alpha/SKILL.md"
printf 'echo hi\n' > "$WORK/src/alpha/scripts/run.sh"

# a zip whose root contains a skill folder "beta"
mkdir -p "$WORK/zipsrc/beta"
printf -- '---\nname: beta\ndescription: test skill beta\n---\nhi\n' > "$WORK/zipsrc/beta/SKILL.md"
( cd "$WORK/zipsrc" && zip -qr "$WORK/beta.zip" beta )

PROJ="$WORK/project"; mkdir -p "$PROJ"

# --- load: local path -------------------------------------------------------
./main.sh --load -p "$WORK/src/alpha" --cat "$CATEGORY" >/dev/null
check "load --path imports skill"        test -f "skills/$CATEGORY/alpha/SKILL.md"
check "load --path keeps subfolders"     test -f "skills/$CATEGORY/alpha/scripts/run.sh"

# --- load: zip --------------------------------------------------------------
./main.sh --load -f "$WORK/beta.zip" --cat "$CATEGORY" >/dev/null
check "load --file imports zip skill"     test -f "skills/$CATEGORY/beta/SKILL.md"

# --- install: project scope, single skill -----------------------------------
./main.sh --install "--$CATEGORY/alpha" --claude -p "$PROJ" >/dev/null
check "install creates project symlink"   test -L "$PROJ/.claude/skills/alpha"
check "symlink resolves to repo skill"    test -f "$PROJ/.claude/skills/alpha/SKILL.md"

# --- install: whole category ------------------------------------------------
./main.sh --install "--$CATEGORY" --antigravity -p "$PROJ" >/dev/null
check "install category links alpha"      test -L "$PROJ/.agents/skills/alpha"
check "install category links beta"       test -L "$PROJ/.agents/skills/beta"

# --- remove: single skill (needs y/n confirm) -------------------------------
printf 'y\n' | ./main.sh --remove "--$CATEGORY/alpha" --claude -p "$PROJ" >/dev/null
check "remove deletes the symlink"        test ! -e "$PROJ/.claude/skills/alpha"

# --- remove: declining aborts -----------------------------------------------
printf 'n\n' | ./main.sh --remove "--$CATEGORY/beta" --antigravity -p "$PROJ" >/dev/null 2>&1 || true
check "declining keeps the symlink"       test -L "$PROJ/.agents/skills/beta"

# --- summary ----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
