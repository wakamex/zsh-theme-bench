#!/usr/bin/env zsh

ztb_adapter_load() {
  typeset -gA FG FX
  FG[071]=
  FG[124]=
  FG[242]=
  FX[bold]=
  FX[no-bold]=
  FX[reset]=

  source "$ZTB_THEME_ROOT/wakamex.zsh-theme"
}

ztb_adapter_cancel() {
  _wakamex_git_cancel
}

ztb_adapter_collect() {
  local directory=$1 field
  typeset -ga ztb_adapter_fields=()
  while IFS= read -r -d '' field; do
    ztb_adapter_fields+=("$field")
  done < <(_wakamex_git_collect "$directory")
}

ztb_adapter_identity() {
  local directory=$1
  typeset -ga reply=()
  _wakamex_git_identity "$directory"
}

ztb_adapter_apply_fields() {
  local directory=$1
  shift
  _wakamex_git_apply 0 "$directory" "$@"
}

ztb_adapter_cached_prompt() {
  _wakamex_prompt_precmd
}

ztb_adapter_async_start() {
  _wakamex_git_start
  _wakamex_git_watch
}

ztb_adapter_async_drain() {
  local deadline=$(( EPOCHREALTIME + 30 ))
  local -i fd

  while (( _WAKAMEX_GIT_FD >= 0 && EPOCHREALTIME < deadline )); do
    fd=$_WAKAMEX_GIT_FD
    _wakamex_git_read "$fd" 0 0.1
  done

  (( _WAKAMEX_GIT_FD < 0 ))
}

ztb_adapter_fd() {
  REPLY=$_WAKAMEX_GIT_FD
}

ztb_adapter_pid() {
  REPLY=$_WAKAMEX_GIT_PID
}
