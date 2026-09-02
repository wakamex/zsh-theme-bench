#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail
setopt typeset_silent
zmodload zsh/datetime zsh/system

source "$ZTB_ROOT/internal/stats.zsh"
source "$ZTB_ADAPTER"
ztb_adapter_load
ztb_adapter_cancel

typeset -ga ztb_zle_calls=()
zle() {
  ztb_zle_calls+=("${(j: :)@}")
  return 0
}

typeset -ga ztb_check_names=()
typeset -gA ztb_checks=()
typeset -gi ztb_failures=0

ztb_check() {
  local name=$1
  local -i passed=$2
  ztb_check_names+=("$name")
  ztb_checks[$name]=$passed
  (( passed )) || (( ++ztb_failures ))
  return 0
}

ztb_fd_count() {
  local -a descriptors=(/proc/$$/fd/*(N))
  REPLY=${#descriptors}
}

ztb_measure_identity_once() {
  ztb_adapter_identity "$ZTB_TARGET_REPO"
}

ztb_measure_collect_once() {
  ztb_adapter_collect "$ZTB_TARGET_REPO"
}

ztb_measure_fixture_collect_once() {
  ztb_adapter_collect "$ZTB_FIXTURE"
}

ztb_measure_cached_prompt_once() {
  ztb_adapter_cached_prompt
}

ztb_measure_async_schedule() {
  local -a samples=()
  local -F start elapsed
  local -i iteration

  for (( iteration = 1; iteration <= ZTB_ITERATIONS; ++iteration )); do
    ztb_adapter_cancel
    start=$EPOCHREALTIME
    ztb_adapter_async_start
    elapsed=$(( (EPOCHREALTIME - start) * 1000 ))
    samples+=("$elapsed")
    ztb_adapter_cancel
  done
  ztb_median "${samples[@]}"
}

ztb_measure_async_ready() {
  local -a samples=()
  local -F start elapsed
  local -i iteration

  for (( iteration = 1; iteration <= ZTB_ITERATIONS; ++iteration )); do
    ztb_adapter_cancel
    start=$EPOCHREALTIME
    ztb_adapter_async_start
    ztb_adapter_async_drain || return 1
    elapsed=$(( (EPOCHREALTIME - start) * 1000 ))
    samples+=("$elapsed")
  done
  ztb_median "${samples[@]}"
}

ztb_measure_sync_timeout() {
  local -a samples=()
  local -F start elapsed
  local -i iteration fd

  for (( iteration = 1; iteration <= ZTB_ITERATIONS; ++iteration )); do
    exec {fd}< <(sleep 0.1)
    start=$EPOCHREALTIME
    _wakamex_git_read "$fd" 0 0.003
    elapsed=$(( (EPOCHREALTIME - start) * 1000 ))
    samples+=("$elapsed")
    { exec {fd}<&- } 2>/dev/null
  done
  ztb_median "${samples[@]}"
}

cd -q -- "$ZTB_TARGET_REPO"
ztb_adapter_collect "$PWD"
(( ${#ztb_adapter_fields} == 7 )) || {
  print -u2 -r -- "adapter returned ${#ztb_adapter_fields} fields, expected 7"
  return 1
}
ztb_adapter_apply_fields "$PWD" "${ztb_adapter_fields[@]}"

ztb_measure cached_prompt_ms ztb_measure_cached_prompt_once "$ZTB_ITERATIONS"
local cached_prompt_ms=$REPLY
ztb_measure git_identity_ms ztb_measure_identity_once "$ZTB_ITERATIONS"
local git_identity_ms=$REPLY
ztb_measure git_status_ms ztb_measure_collect_once "$ZTB_ITERATIONS"
local git_status_ms=$REPLY
ztb_measure fixture_clean_status_ms ztb_measure_fixture_collect_once "$ZTB_ITERATIONS"
local fixture_clean_status_ms=$REPLY
ztb_measure_async_schedule
local async_schedule_ms=$REPLY
ztb_measure_async_ready
local async_ready_ms=$REPLY
ztb_measure_sync_timeout
local sync_wait_ms=$REPLY

local stderr_marker
stderr_marker=$(
  exec 2>&1
  local -i release_fd
  exec {release_fd}< <(:)
  _WAKAMEX_GIT_FD=$release_fd
  _WAKAMEX_GIT_PID=-1
  _wakamex_git_release 0
  print -u2 -n stderr-survived
)
local -i check_passed=0
[[ $stderr_marker == stderr-survived ]] && check_passed=1
ztb_check stderr_preserved "$check_passed"

local -i fd_before fd_after cycle
local benchmark_pwd=$PWD
cd -q -- "$ZTB_FIXTURE"
ztb_fd_count
fd_before=$REPLY
for (( cycle = 1; cycle <= 25; ++cycle )); do
  ztb_adapter_async_start
  ztb_adapter_async_drain || break
done
ztb_fd_count
fd_after=$REPLY
ztb_check descriptor_cleanup $(( fd_after == fd_before ))
ztb_adapter_fd
local released_fd=$REPLY
ztb_adapter_pid
local released_pid=$REPLY
ztb_check worker_cleanup $(( released_fd == -1 && released_pid == -1 ))
cd -q -- "$benchmark_pwd"

WAKAMEX_GIT_CACHE_PWD=sentinel
WAKAMEX_GIT_FOUND=0
_WAKAMEX_GIT_REQUEST_PWD=$ZTB_FIXTURE
_wakamex_git_apply 0 "$ZTB_FIXTURE" 1 "$ZTB_FIXTURE" main main ± '' '' || true
check_passed=0
[[ $WAKAMEX_GIT_CACHE_PWD == sentinel && $WAKAMEX_GIT_FOUND == 0 ]] && check_passed=1
ztb_check stale_result_ignored "$check_passed"

local saved_worker=${functions[_wakamex_git_worker]}
_wakamex_git_worker() {
  local request_pwd=$1
  sleep 0.03
  _wakamex_git_emit I 1 "$request_pwd" main main ± '' ''
  sleep 0.01
  _wakamex_git_emit S 1 "$request_pwd" main main ± '' ''
}

ztb_adapter_cancel
_wakamex_git_request
for (( cycle = 1; cycle <= 20; ++cycle )); do
  _wakamex_git_request
done
local -i refresh_was_pending=$_WAKAMEX_GIT_REFRESH_PENDING
ztb_adapter_async_drain
ztb_check rapid_prompts_coalesced $(( refresh_was_pending == 1 && _WAKAMEX_GIT_FD == -1 ))
functions[_wakamex_git_worker]=$saved_worker

ztb_adapter_cancel
_wakamex_git_worker() {
  sleep 1
}
_wakamex_git_request
local -i worker_before_preexec=$_WAKAMEX_GIT_PID
_wakamex_prompt_preexec command
ztb_check preexec_cancels_worker $(( worker_before_preexec > 0 && _WAKAMEX_GIT_FD == -1 && _WAKAMEX_GIT_PID == -1 ))
functions[_wakamex_git_worker]=$saved_worker

ztb_zle_calls=()
_WAKAMEX_GIT_REQUEST_PWD=$PWD
WAKAMEX_GIT_CACHE_PWD=
local repaint_message
printf -v repaint_message '%s\0' I 1 "$PWD" repaint repaint ±/repaint '' ''
_wakamex_git_feed "$repaint_message" 1
check_passed=0
(( ${ztb_zle_calls[(Ie).reset-prompt]} && ${ztb_zle_calls[(Ie)-R]} )) && check_passed=1
ztb_check async_repaint "$check_passed"

print -r -- untracked > "$ZTB_FIXTURE/untracked"
ztb_adapter_collect "$ZTB_FIXTURE"
check_passed=0
[[ $ztb_adapter_fields[6] == *\?* ]] && check_passed=1
ztb_check untracked_detected "$check_passed"
ztb_measure fixture_untracked_status_ms ztb_measure_fixture_collect_once "$ZTB_ITERATIONS"
local fixture_untracked_status_ms=$REPLY
command rm -- "$ZTB_FIXTURE/untracked"

print -r -- changed >> "$ZTB_FIXTURE/file-1"
ztb_adapter_collect "$ZTB_FIXTURE"
check_passed=0
[[ $ztb_adapter_fields[6] == *\!* ]] && check_passed=1
ztb_check tracked_change_detected "$check_passed"
ztb_measure fixture_dirty_status_ms ztb_measure_fixture_collect_once "$ZTB_ITERATIONS"
local fixture_dirty_status_ms=$REPLY
command git -C "$ZTB_FIXTURE" restore file-1

print -r -- staged > "$ZTB_FIXTURE/staged"
command git -C "$ZTB_FIXTURE" add staged
ztb_adapter_collect "$ZTB_FIXTURE"
check_passed=0
[[ $ztb_adapter_fields[6] == *+* ]] && check_passed=1
ztb_check staged_change_detected "$check_passed"
ztb_measure fixture_staged_status_ms ztb_measure_fixture_collect_once "$ZTB_ITERATIONS"
local fixture_staged_status_ms=$REPLY
command git -C "$ZTB_FIXTURE" reset -q HEAD staged
command rm -- "$ZTB_FIXTURE/staged"

local git_log=$ZTB_SCRATCH/git-environment.log
local real_git=${commands[git]}
local old_path=$PATH
: > "$git_log"
PATH="$ZTB_GIT_PROBE_BIN:$PATH"
rehash
ZTB_GIT_LOG=$git_log ZTB_REAL_GIT=$real_git ztb_adapter_collect "$ZTB_FIXTURE"
PATH=$old_path
rehash
local -a optional_lock_values=("${(@f)$(< "$git_log")}")
local -i locks_disabled=1
local lock_value
for lock_value in "${optional_lock_values[@]}"; do
  [[ $lock_value == 0 ]] || locks_disabled=0
done
(( ${#optional_lock_values} )) || locks_disabled=0
ztb_check optional_locks_disabled "$locks_disabled"

ztb_check sync_wait_bounded $(( sync_wait_ms < 20 ))

local tracked_files
tracked_files=$(command git -C "$ZTB_TARGET_REPO" ls-files 2>/dev/null | command wc -l)
tracked_files=${tracked_files//[[:space:]]/}

print -r -- "theme_root=$ZTB_THEME_ROOT"
print -r -- "repository=$ZTB_TARGET_REPO"
print -r -- "iterations=$ZTB_ITERATIONS"
print -r -- "tracked_files=${tracked_files:-0}"
print -r -- "fixture_files=$ZTB_FIXTURE_FILES"
print -r -- "cached_prompt_ms=$cached_prompt_ms"
print -r -- "git_identity_ms=$git_identity_ms"
print -r -- "git_status_ms=$git_status_ms"
print -r -- "fixture_clean_status_ms=$fixture_clean_status_ms"
print -r -- "fixture_dirty_status_ms=$fixture_dirty_status_ms"
print -r -- "fixture_staged_status_ms=$fixture_staged_status_ms"
print -r -- "fixture_untracked_status_ms=$fixture_untracked_status_ms"
print -r -- "async_schedule_ms=$async_schedule_ms"
print -r -- "async_ready_ms=$async_ready_ms"
print -r -- "sync_wait_ms=$sync_wait_ms"
print -r -- "fd_delta=$(( fd_after - fd_before ))"

local check_name
for check_name in "$ztb_check_names[@]"; do
  print -r -- "check_${check_name}=$ztb_checks[$check_name]"
done

ztb_adapter_cancel
(( ztb_failures == 0 ))
