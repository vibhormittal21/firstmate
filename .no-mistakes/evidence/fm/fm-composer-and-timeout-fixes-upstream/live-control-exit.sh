#!/usr/bin/env bash
# Live end-to-end stop-command scenario: drive the real firstmate control plane
# (bin/fm-control.sh exit) against a REAL opencode 2.0.18 pane in an isolated
# Herdr lab session and a marked disposable lab home.
set -u
ROOT="/Users/vibhormittal/.no-mistakes/worktrees/4ab467ae808e/01M3J8S2ZW2PM5N6RQHHZ3A6V4"
EV="/Users/vibhormittal/.no-mistakes/evidence/01M3J8S2ZW2PM5N6RQHHZ3A6V4"
cd "$ROOT" || exit 1
unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE \
      FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE 2>/dev/null || true
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane
unset FM_GATE_REFUSE_BYPASS
. "$ROOT/bin/fm-backend.sh"
fm_backend_source herdr || { echo "backend source failed"; exit 1; }

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
bin/fm-lab-home.sh create "$LAB" >/dev/null || { echo "lab home failed"; exit 1; }
mkdir -p "$LAB/tmux"
SESSION=$(bin/fm-herdr-lab.sh name composer)
echo "session=$SESSION"
echo "lab_home=$LAB"
fm_herdr_lab_prepare "$SESSION" || { echo "prepare failed"; exit 1; }
export HERDR_SESSION="$SESSION"

cleanup() {
  echo "--- teardown $SESSION ---"
  bin/fm-herdr-lab.sh teardown "$SESSION" 2>&1 || true
  echo "--- remove lab home ---"
  rm -rf "$LAB"
}
trap cleanup EXIT

CONTAINER_RAW=$(fm_backend_herdr_container_ensure /tmp) || { echo "container_ensure failed"; exit 1; }
CONTAINER=${CONTAINER_RAW%%$'\t'*}
WSID=${CONTAINER#*:}
SEEDED=${CONTAINER_RAW#*$'\t'}
TASK_IDS=$(fm_backend_herdr_create_task "$CONTAINER" "fm-control-live" "$ROOT" "$SEEDED") || { echo "create_task failed"; exit 1; }
read -r TAB PANE <<PAIR
$TASK_IDS
PAIR
TARGET="$SESSION:$PANE"
echo "target=$TARGET"

fm_backend_herdr_send_literal "$TARGET" 'opencode' || { echo "launch failed"; exit 1; }
fm_backend_herdr_send_key "$TARGET" Enter || { echo "launch enter failed"; exit 1; }
verdict=''
i=0
while [ "$i" -lt 60 ]; do
  verdict=$(fm_backend_herdr_composer_state "$TARGET" 2>/dev/null)
  [ "$verdict" = empty ] && break
  i=$((i + 1))
  sleep 1
done
echo "pre_exit_composer_verdict=$verdict"
echo "pre_exit_agent_state=$(fm_backend_herdr_agent_state "$TARGET" 2>&1)"

ID="opencode-stop-probe"
META="$LAB/state/$ID.meta"
{
  echo "window=$TARGET"
  echo "endpoint_task_id=$ID"
  echo "worktree=$ROOT"
  echo "project=$ROOT"
  echo "harness=opencode"
  echo "kind=ship"
  echo "mode=no-mistakes"
  echo "yolo=off"
  echo "model=default"
  echo "effort=default"
  echo "spawn_gen=s-live-probe"
  echo "backend=herdr"
  echo "herdr_session=$SESSION"
  echo "herdr_workspace_id=$WSID"
  echo "herdr_tab_id=$TAB"
  echo "herdr_pane_id=$PANE"
} > "$META"

# Pre-fix comparison without touching the worktree: a private copy of bin/ with
# the base-commit composer library, driven exactly like the real one.
mkdir -p "$LAB/repo"
cp -R "$ROOT/bin" "$LAB/repo/bin"
git -C "$ROOT" show 8c5493a0e17aa92f1c4dfaf868df196e02d49c8e:bin/fm-composer-lib.sh > "$LAB/repo/bin/fm-composer-lib.sh"
echo "--- PRE-FIX fm-control.sh exit $ID ---"
out=$(FM_HOME="$LAB" "$LAB/repo/bin/fm-control.sh" "$ID" exit 2>&1); rc=$?
echo "prefix_control_exit_rc=$rc"
echo "$out"
echo "prefix_post_agent_state=$(fm_backend_herdr_agent_state "$TARGET" 2>&1)"

echo "--- FIXED fm-control.sh exit $ID ---"
out=$(FM_HOME="$LAB" bin/fm-control.sh "$ID" exit 2>&1); rc=$?
echo "control_exit_rc=$rc"
echo "$out"
echo "--- opencode agent state after exit ---"
echo "post_exit_agent_state=$(fm_backend_herdr_agent_state "$TARGET" 2>&1)"
echo "DONE"
