#!/usr/bin/env bash
# Live composer validation for the opencode 2.x status-bar fix.
#
# Drives the REAL product (bin/fm-backend.sh -> herdr adapter ->
# bin/fm-composer-lib.sh) against a REAL opencode 2.0.18 pane in an isolated,
# throwaway Herdr lab session, then compares the same live capture against the
# pre-fix library checked out from the base commit.
set -u
ROOT="/Users/vibhormittal/.no-mistakes/worktrees/4ab467ae808e/01M3J8S2ZW2PM5N6RQHHZ3A6V4"
EV="/Users/vibhormittal/.no-mistakes/evidence/01M3J8S2ZW2PM5N6RQHHZ3A6V4"
BASE_COMMIT="8c5493a0e17aa92f1c4dfaf868df196e02d49c8e"
cd "$ROOT" || exit 1
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane
. "$ROOT/bin/fm-backend.sh"
fm_backend_source herdr || { echo "backend source failed"; exit 1; }

SESSION=$(bin/fm-herdr-lab.sh name composer)
echo "session=$SESSION"
fm_herdr_lab_prepare "$SESSION" || { echo "prepare failed"; exit 1; }
export HERDR_SESSION="$SESSION"

cleanup() {
  echo "--- teardown $SESSION ---"
  bin/fm-herdr-lab.sh teardown "$SESSION" 2>&1 || true
}
trap cleanup EXIT

CONTAINER_RAW=$(fm_backend_herdr_container_ensure /tmp) || { echo "container_ensure failed"; exit 1; }
CONTAINER=${CONTAINER_RAW%%$'\t'*}
SEEDED=${CONTAINER_RAW#*$'\t'}
TASK_IDS=$(fm_backend_herdr_create_task "$CONTAINER" "fm-composer-live" "$ROOT" "$SEEDED") || { echo "create_task failed"; exit 1; }
read -r TAB PANE <<PAIR
$TASK_IDS
PAIR
TARGET="$SESSION:$PANE"
echo "target=$TARGET"

fm_backend_herdr_send_literal "$TARGET" 'opencode' || { echo "launch failed"; exit 1; }
fm_backend_herdr_send_key "$TARGET" Enter || { echo "launch enter failed"; exit 1; }

echo "--- wait for the real idle composer through the adapter ---"
verdict=''
i=0
while [ "$i" -lt 60 ]; do
  verdict=$(fm_backend_herdr_composer_state "$TARGET" 2>/dev/null)
  [ "$verdict" = empty ] && break
  i=$((i + 1))
  sleep 1
done
echo "target_adapter_idle_verdict=$verdict"
echo "opencode_version=$(opencode --version 2>/dev/null | head -1)"
echo "herdr_agent_identity=$(fm_backend_herdr_composer_identity "$TARGET" 2>&1)"

CAPS=$'styled=1\ncursor=0\nidentity=1'
fm_backend_herdr_visible_capture_ansi "$TARGET" > "$EV/live-opencode-idle.ansi"
ANSI=$(cat "$EV/live-opencode-idle.ansi")
echo "--- visible pane (plain) ---"
fm_backend_herdr_visible_capture "$TARGET" | grep '[^[:space:]]'

# --- same live capture through the pre-fix library ---------------------------
BASE_LIB="$EV/fm-composer-lib.base.sh"
git -C "$ROOT" show "$BASE_COMMIT:bin/fm-composer-lib.sh" > "$BASE_LIB"
classify_with() { # <lib> <cap>
  bash -c '
    . "$1"
    v=$(fm_composer_classify_screen "$2" "$3")
    if [ "$v" = need-identity ]; then
      v=$(fm_composer_classify_screen "$2" "$3" "" "opencode\tidle")
      [ "$v" != need-identity ] || v=unknown
    fi
    printf "%s" "$v"
  ' _ "$1" "$CAPS" "$2"
}
echo "live_idle_verdict_prefix=$(classify_with "$BASE_LIB" "$ANSI")"
echo "live_idle_verdict_target=$(classify_with "$ROOT/bin/fm-composer-lib.sh" "$ANSI")"

# --- real typed draft must not be masked by the status bar -------------------
fm_backend_herdr_send_literal "$TARGET" 'live composer probe text' || echo "type failed"
sleep 1
typed=$(fm_backend_herdr_composer_state "$TARGET" 2>/dev/null)
echo "target_adapter_typed_verdict=$typed"
TYPED_ANSI=$(fm_backend_herdr_visible_capture_ansi "$TARGET")
echo "live_typed_verdict_target=$(classify_with "$ROOT/bin/fm-composer-lib.sh" "$TYPED_ANSI")"

# --- adversarial: the exemption must stay scoped to the left-bar shape -------
STATUS=$'  ~/.treehouse/x:fm/fm-branch  186.6K (19%) · 0.12  ctrl+p commands'
BOX=$'╭────────────────────────╮\n│ ❯                      │\n╰────────────────────────╯\n'"$STATUS"
DEAD=$'  ┃\n  ┃\n  ┃  Build · DeepSeek V4.1 Flash DeepSeek\n  ╹▀▀▀▀\nvibhormittal@host repo %'
echo "box_status_verdict_target=$(classify_with "$ROOT/bin/fm-composer-lib.sh" "$BOX")"
echo "dead_shell_verdict_target=$(classify_with "$ROOT/bin/fm-composer-lib.sh" "$DEAD")"
echo "box_status_verdict_prefix=$(classify_with "$BASE_LIB" "$BOX")"
echo "dead_shell_verdict_prefix=$(classify_with "$BASE_LIB" "$DEAD")"
echo "DONE"
