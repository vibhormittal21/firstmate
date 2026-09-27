#!/usr/bin/env bash
# Live validation for the stock-macOS-bash 3.2 owner-capture fix in
# bin/fm-timeout-lib.sh. MUST run under stock /bin/bash (3.2); the rest of the
# fleet's shell is 3.2 on a stock macOS host.
#
# Drives the real product entry points:
#   - bin/fm-timeout-lib.sh's fm_exec_timed (the bounded-run helper the spawn bug
#     is about), and
#   - bin/fm-backlog-transition-lib.sh's fm_tasks_axi (the bounded call the
#     spawn dispatch transition runs after the worker is already started),
# with the pre-fix library (base commit) and the fixed library, on the SAME
# host and command.
set -u
ROOT="/Users/vibhormittal/.no-mistakes/worktrees/4ab467ae808e/01M3J8S2ZW2PM5N6RQHHZ3A6V4"
EV="/Users/vibhormittal/.no-mistakes/evidence/01M3J8S2ZW2PM5N6RQHHZ3A6V4"
BASE_COMMIT="8c5493a0e17aa92f1c4dfaf868df196e02d49c8e"
cd "$ROOT" || exit 1

BASE_LIB="$EV/fm-timeout-lib.base.sh"
git -C "$ROOT" show "$BASE_COMMIT:bin/fm-timeout-lib.sh" > "$BASE_LIB"
TARGET_LIB="$ROOT/bin/fm-timeout-lib.sh"

echo "bash_version=$BASH_VERSION"
echo "bash_path=$BASH"
echo "bashpid_probe=$(bash -c 'set -u; printf "%s" "${BASHPID:-UNSET}"')"
echo "tasks_axi=$(command -v tasks-axi)"
echo "tasks_axi_version=$(tasks-axi --version 2>&1)"

# 1) The bounded-run helper directly: real command, real watchdog.
echo "--- fm_exec_timed: fixed library ---"
out=$( ( . "$TARGET_LIB"; fm_exec_timed 5 1 bash -c 'echo bounded-ok' ) 2>&1 ); rc=$?
echo "target_exec_out=$out"
echo "target_exec_rc=$rc"
echo "--- fm_exec_timed: pre-fix library ---"
out=$( ( . "$BASE_LIB"; fm_exec_timed 5 1 bash -c 'echo bounded-ok' ) 2>&1 ); rc=$?
echo "prefix_exec_out=$out"
echo "prefix_exec_rc=$rc"

# 2) The owned bound itself still fires with the fixed library.
echo "--- fm_exec_timed bound: fixed library ---"
out=$( ( . "$TARGET_LIB"; fm_exec_timed 1 1 sleep 30 ) 2>&1 ); rc=$?
echo "target_bound_rc=$rc"

# 3) The dispatch transition's real bounded call (fm_tasks_axi). The lib's own
#    source path loads the fixed helper; re-sourcing the base lib after it
#    reproduces the pre-fix dispatch transition on the same command.
echo "--- fm_tasks_axi (dispatch transition's bounded call): fixed library ---"
out=$( (
  . "$ROOT/bin/fm-tasks-axi-lib.sh"
  . "$ROOT/bin/fm-backlog-transition-lib.sh"
  FM_TASKS_AXI_TIMEOUT=10 fm_tasks_axi --version
) 2>&1 ); rc=$?
echo "target_dispatch_out=$out"
echo "target_dispatch_rc=$rc"
echo "--- fm_tasks_axi (dispatch transition's bounded call): pre-fix helper ---"
out=$( (
  . "$ROOT/bin/fm-tasks-axi-lib.sh"
  . "$ROOT/bin/fm-backlog-transition-lib.sh"
  . "$BASE_LIB"
  FM_TASKS_AXI_TIMEOUT=10 fm_tasks_axi --version
) 2>&1 ); rc=$?
echo "prefix_dispatch_out=$out"
echo "prefix_dispatch_rc=$rc"
echo "DONE"
