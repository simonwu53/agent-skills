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
# A skill is "installed" if it's a symlink or a copied dir holding SKILL.md.
is_installed() { [ -L "$1" ] || [ -f "$1/SKILL.md" ]; }

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

# --- install: project scope, single skill (copy is the default) -------------
./main.sh --install --skill "$CATEGORY/alpha" --claude -p "$PROJ" >/dev/null
check "install copies the skill"          test -f "$PROJ/.claude/skills/alpha/SKILL.md"
check "default install is a copy, not link" test ! -L "$PROJ/.claude/skills/alpha"
check "copy keeps subfolders"             test -f "$PROJ/.claude/skills/alpha/scripts/run.sh"

# --- install: --symlink opts into soft links --------------------------------
printf 'y\n' | ./main.sh --install --skill "$CATEGORY/alpha" --claude -p "$PROJ" --symlink >/dev/null
check "--symlink creates a symlink"       test -L "$PROJ/.claude/skills/alpha"

# --- install: multiple --skill selectors at once ----------------------------
printf 'y\n' | ./main.sh --install --skill "$CATEGORY/alpha" "$CATEGORY/beta" --antigravity -p "$PROJ" >/dev/null
check "multi-skill installs alpha"        is_installed "$PROJ/.agents/skills/alpha"
check "multi-skill installs beta"         is_installed "$PROJ/.agents/skills/beta"

# --- install: whole category ------------------------------------------------
printf 'y\n' | ./main.sh --install --skill "$CATEGORY" --antigravity -p "$PROJ" >/dev/null
check "install category installs alpha"   is_installed "$PROJ/.agents/skills/alpha"
check "install category installs beta"    is_installed "$PROJ/.agents/skills/beta"

# --- install: warns before overwriting an existing skill (declining skips) ---
printf 'n\n' | ./main.sh --install --skill "$CATEGORY/alpha" --antigravity -p "$PROJ" --keep >/dev/null
check "declining overwrite keeps skill"   is_installed "$PROJ/.agents/skills/alpha"

# --- update: overwrites without prompting, leaves others intact -------------
./main.sh --update --skill "$CATEGORY/alpha" --antigravity -p "$PROJ" >/dev/null
check "update overwrites alpha silently"  is_installed "$PROJ/.agents/skills/alpha"
check "update leaves other skills (beta)" is_installed "$PROJ/.agents/skills/beta"

# --- list: repo library and installed skills --------------------------------
check "list repo shows category"  sh -c "./main.sh --list | grep -q '$CATEGORY/'"
check "list repo shows skill"     sh -c "./main.sh --list | grep -q -- '- alpha'"
check "list installed shows skill" sh -c "./main.sh --list --antigravity -p '$PROJ' | grep -q -- '- alpha'"

# --- remove: single skill by flat name (needs y/n confirm) ------------------
printf 'y\n' | ./main.sh --remove --skill alpha --claude -p "$PROJ" >/dev/null
check "remove deletes the skill"          test ! -e "$PROJ/.claude/skills/alpha"

# --- remove: declining aborts -----------------------------------------------
printf 'n\n' | ./main.sh --remove --skill beta --antigravity -p "$PROJ" >/dev/null 2>&1 || true
check "declining keeps the skill"         is_installed "$PROJ/.agents/skills/beta"

# --- remove: no --skill clears every skill for the tool ---------------------
printf 'y\n' | ./main.sh --remove --antigravity -p "$PROJ" >/dev/null
check "remove-all clears alpha"           test ! -e "$PROJ/.agents/skills/alpha"
check "remove-all clears beta"            test ! -e "$PROJ/.agents/skills/beta"

# --- pin: installs immediately + records config -----------------------------
PROJ2="$WORK/project2"; mkdir -p "$PROJ2"
./main.sh --pin --skill "$CATEGORY/alpha" --claude -p "$PROJ2" >/dev/null
check "pin installs the skill now"        is_installed "$PROJ2/.claude/skills/alpha"
check "pin records it in config"          in_file "skill: $CATEGORY/alpha" "$CONFIG_FILE"

# --- pin survives an install-clear (no --keep) ------------------------------
printf 'y\n' | ./main.sh --install --skill "$CATEGORY/beta" --claude -p "$PROJ2" >/dev/null
check "install adds the new skill"        is_installed "$PROJ2/.claude/skills/beta"
check "pinned skill survives the clear"   is_installed "$PROJ2/.claude/skills/alpha"

# --- unpin: removes skill + config ------------------------------------------
./main.sh --unpin --skill "$CATEGORY/alpha" --claude -p "$PROJ2" >/dev/null
check "unpin removes the skill"           test ! -e "$PROJ2/.claude/skills/alpha"
check "unpin clears the config"           not_in_file "skill: $CATEGORY/alpha" "$CONFIG_FILE"

# --- remove warns on a pinned skill, de-pins on confirm ---------------------
./main.sh --pin --skill "$CATEGORY/beta" --claude -p "$PROJ2" >/dev/null
printf 'n\n' | ./main.sh --remove --skill beta --claude -p "$PROJ2" >/dev/null 2>&1 || true
check "declining keeps pinned skill"      is_installed "$PROJ2/.claude/skills/beta"
check "declining keeps pin config"        in_file "skill: $CATEGORY/beta" "$CONFIG_FILE"
printf 'y\n' | ./main.sh --remove --skill beta --claude -p "$PROJ2" >/dev/null
check "confirming removes pinned skill"   test ! -e "$PROJ2/.claude/skills/beta"
check "confirming strips pin config"      not_in_file "skill: $CATEGORY/beta" "$CONFIG_FILE"

# --- unload deletes the repo source -----------------------------------------
printf 'n\n' | ./main.sh --unload --skill "$CATEGORY/beta" >/dev/null 2>&1 || true
check "declining unload keeps source"     test -f "skills/$CATEGORY/beta/SKILL.md"
printf 'y\n' | ./main.sh --unload --skill "$CATEGORY/alpha" >/dev/null
check "unload deletes the source"         test ! -e "skills/$CATEGORY/alpha"

# --- summary ----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
