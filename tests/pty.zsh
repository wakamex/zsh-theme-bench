#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail
setopt extended_glob typeset_silent
zmodload zsh/datetime zsh/zpty zsh/zselect

local root=${0:A:h:h}
local theme_root=${ZTB_THEME_ROOT:-${root:h}/wakamex-zsh-theme}
local scratch
scratch=$(mktemp -d /var/tmp/zsh-theme-bench-pty.XXXXXX)
[[ -n $scratch && -d $scratch ]] || {
  print -u2 -r -- 'failed to create PTY scratch directory'
  return 1
}

local pty_name=zsh_theme_bench_pty
typeset -gi worker_child_pid=-1
cleanup() {
  zpty -d "$pty_name" 2>/dev/null || true
  if (( worker_child_pid > 0 )) && kill -0 "$worker_child_pid" 2>/dev/null; then
    kill -TERM "$worker_child_pid" 2>/dev/null || true
  fi
  command rm -rf -- "$scratch"
}
trap cleanup EXIT INT TERM

local fixture=$scratch/fixture
command git init -q -b main "$fixture"
command git -C "$fixture" config user.name zsh-theme-bench
command git -C "$fixture" config user.email zsh-theme-bench@example.invalid
print -r -- seed > "$fixture/file"
command git -C "$fixture" add file
command git -C "$fixture" commit -qm seed

local probe_bin=$scratch/bin
command mkdir "$probe_bin"
command ln -s "$root/internal/git-probe" "$probe_bin/git"
local real_git=${commands[git]}

typeset -gi assertions=0
expect_contains() {
  local output=$1 expected=$2 description=$3
  (( ++assertions ))
  if [[ $output != *$expected* ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "missing: ${(qqq)expected}"
    print -u2 -r -- "output:  ${(qqq)output}"
    return 1
  fi
}

expect_excludes() {
  local output=$1 rejected=$2 description=$3
  (( ++assertions ))
  if [[ $output == *$rejected* ]]; then
    print -u2 -r -- "FAIL: $description"
    print -u2 -r -- "found:  ${(qqq)rejected}"
    print -u2 -r -- "output: ${(qqq)output}"
    return 1
  fi
}

expect_true() {
  local -i condition=$1
  local description=$2
  (( ++assertions ))
  if (( ! condition )); then
    print -u2 -r -- "FAIL: $description"
    return 1
  fi
}

typeset -g pty_output=
pty_read_available() {
  local chunk
  while zpty -r -t "$pty_name" chunk 2>/dev/null; do
    pty_output+=$chunk
  done
  return 0
}

pty_wait_for() {
  local expected=$1
  local -F timeout=${2:-3}
  local -F deadline=$(( EPOCHREALTIME + timeout ))

  while (( EPOCHREALTIME < deadline )); do
    pty_read_available
    [[ $pty_output == *$expected* ]] && return 0
    zselect -t 1 2>/dev/null || true
  done

  pty_read_available
  print -u2 -r -- "PTY timeout waiting for ${(qqq)expected}"
  print -u2 -r -- "output: ${(qqq)pty_output}"
  return 1
}

pty_pause() {
  local -F seconds=$1
  local -i hundredths=$(( seconds * 100 + 0.5 ))
  (( hundredths > 0 )) || hundredths=1
  zselect -t "$hundredths" 2>/dev/null || true
  pty_read_available
}

pty_send() {
  zpty -w "$pty_name" "$1"
}

ztb_pty_child() {
  builtin cd -q -- "$fixture"
  export ZDOTDIR=$scratch/zdotdir
  export PATH="$probe_bin:$PATH"
  export ZTB_REAL_GIT=$real_git
  export ZTB_GIT_DELAY=0.12
  export PS1='ZTB_BOOT> '
  export TERM=xterm-256color
  command mkdir -p "$ZDOTDIR"
  exec zsh -dfi
}

zpty -b "$pty_name" ztb_pty_child
pty_wait_for 'ZTB_BOOT>' 5

pty_output=
local setup_command="typeset -gA FG FX; FG[071]=; FG[124]=; FG[242]=; FX[bold]=; FX[no-bold]=; FX[reset]=; PROMPT_DEFAULT_END=\$'ZTB_\\x50TY>'; PROMPT_ROOT_END=\$'ZTB_\\x50TY>'; TIMEFMT=\$'ZTB_\\x54IME %E'; source ${(q)theme_root}/wakamex.zsh-theme; print -r -- \$'ZTB_\\x53ETUP_DONE'"
pty_send "$setup_command"
pty_wait_for 'ZTB_SETUP_DONE' 5
pty_pause 0.35
expect_contains "$pty_output" 'ZTB_PTY>' 'theme prompt rendered in a real PTY'

pty_output=
pty_send "print -u2 -r -- \$'ZTB_\\x53TDERR_OK'; time sleep 0.02; print -r -- \$'ZTB_\\x54IME_DONE'"
pty_wait_for 'ZTB_TIME_DONE' 3
expect_contains "$pty_output" 'ZTB_STDERR_OK' 'stderr survives the real async callback'
expect_contains "$pty_output" 'ZTB_TIME 0.02' 'zsh time output survives the real async callback'

pty_output=
print -r -- untracked > "$fixture/untracked"
pty_send ":; print -r -- \$'ZTB_\\x52EPAINT_STARTED'"
pty_wait_for 'ZTB_REPAINT_STARTED' 3
pty_pause 0.35
expect_contains "$pty_output" '? ZTB_PTY>' 'async Git result repainted the visible prompt'

command rm -- "$fixture/untracked"
pty_output=
pty_send ":; print -r -- \$'ZTB_\\x43LEAN_STARTED'"
pty_wait_for 'ZTB_CLEAN_STARTED' 3
pty_pause 0.35
expect_contains "$pty_output" '± ZTB_PTY>' 'clean async result repainted the visible prompt'

print -r -- stale > "$fixture/untracked"
pty_output=
pty_send ":; print -r -- \$'ZTB_\\x53TALE_SCAN_STARTED'"
pty_wait_for 'ZTB_STALE_SCAN_STARTED' 3
pty_send "cd ${(q)scratch}; print -r -- \$'ZTB_\\x43D_DONE'"
pty_wait_for 'ZTB_CD_DONE' 3
pty_pause 0.35
expect_excludes "$pty_output" '? ZTB_PTY>' 'old-directory result did not repaint after cd'
command rm -- "$fixture/untracked"

pty_output=
pty_send ":; print -r -- \$'ZTB_\\x43ANCEL_SCAN_STARTED'"
pty_wait_for 'ZTB_CANCEL_SCAN_STARTED' 3
pty_send "print -r -- ZTB_STATE=\${_WAKAMEX_GIT_FD}:\${_WAKAMEX_GIT_PID}; print -r -- \$'ZTB_\\x43ANCEL_DONE'"
pty_wait_for 'ZTB_CANCEL_DONE' 3
expect_contains "$pty_output" 'ZTB_STATE=-1:-1' 'preexec cancelled active worker state in the live shell'
pty_pause 0.2

pty_output=
pty_send "typeset -ga ZTB_BASE_FDS=(/proc/\$\$/fd/*(N)); typeset -gi ZTB_BASE_FD_COUNT=\${#ZTB_BASE_FDS}; source ${(q)theme_root}/wakamex.zsh-theme; print -r -- \$'ZTB_\\x52ELOAD_STARTED'"
pty_wait_for 'ZTB_RELOAD_STARTED' 3
pty_pause 0.35
pty_send "typeset -a ZTB_NOW_FDS=(/proc/\$\$/fd/*(N)); print -r -- ZTB_RELOAD=\${#\${(M)precmd_functions:#_wakamex_prompt_precmd}}:\${#\${(M)precmd_functions:#_wakamex_git_request}}:\${#\${(M)preexec_functions:#_wakamex_prompt_preexec}}:\${#\${(M)zshexit_functions:#_wakamex_git_shutdown}}:\$(( \${#ZTB_NOW_FDS} == ZTB_BASE_FD_COUNT )); print -r -- \$'ZTB_\\x52ELOAD_DONE'"
pty_wait_for 'ZTB_RELOAD_DONE' 3
expect_contains "$pty_output" 'ZTB_RELOAD=1:1:1:1:1' 'steady-state reload kept one hook and no extra descriptor'

pty_output=
local worker_pid_file=$scratch/worker-child.pid
pty_send "_wakamex_git_worker() { sleep 10 & print -r -- \$! > ${(q)worker_pid_file}; wait }; print -r -- \$'ZTB_\\x43HILD_SCAN_STARTED'"
pty_wait_for 'ZTB_CHILD_SCAN_STARTED' 3
local -F child_deadline=$(( EPOCHREALTIME + 3 ))
while [[ ! -s $worker_pid_file ]] && (( EPOCHREALTIME < child_deadline )); do
  pty_pause 0.01
done
[[ -s $worker_pid_file ]] || {
  print -u2 -r -- 'PTY worker did not record its child PID'
  return 1
}
worker_child_pid=$(< "$worker_pid_file")
pty_send "print -r -- \$'ZTB_\\x43HILD_CANCELLED'"
pty_wait_for 'ZTB_CHILD_CANCELLED' 3
pty_pause 0.1
local -i child_is_gone=0
kill -0 "$worker_child_pid" 2>/dev/null || child_is_gone=1
expect_true "$child_is_gone" 'preexec cancellation killed the worker child process group'
worker_child_pid=-1

pty_output=
pty_send "readlink /proc/\$\$/fd/2; print -r -- \$'ZTB_\\x46D_DONE'"
pty_wait_for 'ZTB_FD_DONE' 3
expect_contains "$pty_output" '/dev/pts/' 'stderr still points at the PTY'

pty_send exit
print -r -- "PASS: $assertions PTY assertions"
