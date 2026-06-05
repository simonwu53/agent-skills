#!/usr/bin/env bash
# Offline smoke test for main.sh. Touches only temp dirs and skills/_SmokeTest.
# Run from anywhere:  bash test/smoke_test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$REPO_ROOT"

WORK="$(mktemp -d)"
CATEGORY="_SmokeTest"
trap 'rm -rf "$WORK"; rm -rf "skills/$CATEGORY"' EXIT

# Use a throwaway config so we never touch the real config.yaml. The non-default
# name also makes init_config skip the .gitignore mutation.
export CONFIG_FILE="$WORK/test-config.yaml"

pass=0; fail=0
check() { # check <desc> <test-cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then printf 'ok   - %s\n' "$desc"; pass=$((pass+1))
  else printf 'FAIL - %s\n' "$desc"; fail=$((fail+1)); fi
}
in_file()     { grep -q "$1" "$2"; }
not_in_file() { ! grep -q "$1" "$2"; }

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
./main.sh --install --skill "$CATEGORY/alpha" --claude -p "$PROJ" >/dev/null
check "install creates project symlink"   test -L "$PROJ/.claude/skills/alpha"
check "symlink resolves to repo skill"    test -f "$PROJ/.claude/skills/alpha/SKILL.md"

# --- install: whole category ------------------------------------------------
./main.sh --install --skill "$CATEGORY" --antigravity -p "$PROJ" >/dev/null
check "install category links alpha"      test -L "$PROJ/.agents/skills/alpha"
check "install category links beta"       test -L "$PROJ/.agents/skills/beta"

# --- remove: single skill (needs y/n confirm) -------------------------------
printf 'y\n' | ./main.sh --remove --skill "$CATEGORY/alpha" --claude -p "$PROJ" >/dev/null
check "remove deletes the symlink"        test ! -e "$PROJ/.claude/skills/alpha"

# --- remove: declining aborts -----------------------------------------------
printf 'n\n' | ./main.sh --remove --skill "$CATEGORY/beta" --antigravity -p "$PROJ" >/dev/null 2>&1 || true
check "declining keeps the symlink"       test -L "$PROJ/.agents/skills/beta"

# --- pin: links immediately + records config --------------------------------
PROJ2="$WORK/project2"; mkdir -p "$PROJ2"
./main.sh --pin --skill "$CATEGORY/alpha" --claude -p "$PROJ2" >/dev/null
check "pin links the skill now"           test -L "$PROJ2/.claude/skills/alpha"
check "pin records it in config"          in_file "skill: $CATEGORY/alpha" "$CONFIG_FILE"

# --- pin survives an install-clear (no --keep) ------------------------------
printf 'y\n' | ./main.sh --install --skill "$CATEGORY/beta" --claude -p "$PROJ2" >/dev/null
check "install links the new skill"       test -L "$PROJ2/.claude/skills/beta"
check "pinned skill survives the clear"   test -L "$PROJ2/.claude/skills/alpha"

# --- unpin: removes symlink + config ----------------------------------------
./main.sh --unpin --skill "$CATEGORY/alpha" --claude -p "$PROJ2" >/dev/null
check "unpin removes the symlink"         test ! -e "$PROJ2/.claude/skills/alpha"
check "unpin clears the config"           not_in_file "skill: $CATEGORY/alpha" "$CONFIG_FILE"

# --- remove warns on a pinned skill, de-pins on confirm ---------------------
./main.sh --pin --skill "$CATEGORY/beta" --claude -p "$PROJ2" >/dev/null
printf 'n\n' | ./main.sh --remove --skill "$CATEGORY/beta" --claude -p "$PROJ2" >/dev/null 2>&1 || true
check "declining keeps pinned symlink"    test -L "$PROJ2/.claude/skills/beta"
check "declining keeps pin config"        in_file "skill: $CATEGORY/beta" "$CONFIG_FILE"
printf 'y\n' | ./main.sh --remove --skill "$CATEGORY/beta" --claude -p "$PROJ2" >/dev/null
check "confirming removes pinned symlink" test ! -e "$PROJ2/.claude/skills/beta"
check "confirming strips pin config"      not_in_file "skill: $CATEGORY/beta" "$CONFIG_FILE"

# --- unload deletes the repo source -----------------------------------------
printf 'n\n' | ./main.sh --unload --skill "$CATEGORY/beta" >/dev/null 2>&1 || true
check "declining unload keeps source"     test -f "skills/$CATEGORY/beta/SKILL.md"
printf 'y\n' | ./main.sh --unload --skill "$CATEGORY/alpha" >/dev/null
check "unload deletes the source"         test ! -e "skills/$CATEGORY/alpha"

# --- summary ----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
