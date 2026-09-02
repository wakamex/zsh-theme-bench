#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail -o extended_glob
setopt typeset_silent
zmodload zsh/datetime zsh/zpty zsh/zselect

local root=${0:A:h:h}
local script_name=${0:t}
local dependency_root=${root:h}
local omz_dir=${ZTB_OMZ_DIR:-${ZSH:-$HOME/.oh-my-zsh}}
local wakamex_dir=${ZTB_WAKAMEX_DIR:-$dependency_root/wakamex-zsh-theme}
local pure_dir=${ZTB_PURE_DIR:-$dependency_root/pure}
local powerlevel10k_dir=${ZTB_POWERLEVEL10K_DIR:-$dependency_root/powerlevel10k}
local powerlevel10k_gitstatusd=${ZTB_POWERLEVEL10K_GITSTATUSD:-}
local omz_commit=2264a8042763edf2620cfe32d96b096e1f3d26aa
local pure_commit=dbefd0dcafaa3ac7d7222ca50890d9d0c97f7ca2
local powerlevel10k_commit=35833ea15f14b71dbcebc7e54c104d8d56ca5268
local scratch_parent=/var/tmp
local -i iterations=5
local -i fixture_files=1000
local -i settle_ms=150
local samples_output=
local telemetry_output=
local -a targets=(
  raw
  wakamex
  robbyrussell
  agnoster
  bureau
  Soliah
  steeef
  apple
  mortalscumbag
  ys
  bira
  pure
  powerlevel10k-pure
  powerlevel10k-fallback
)
local -a valid_targets=(direct-git "$targets[@]")
local -a requested_targets=()

usage() {
  print -r -- "usage: $script_name [OPTION].."
  print -r --
  print -r -- 'Run the core prompt matrix in isolated interactive PTYs.'
  print -r -- 'Progress is written to stderr and result TSV is written to stdout.'
  print -r --
  print -r -- 'OPTIONS'
  print -r -- '  -h, --help'
  print -r -- '  -i, --iterations NUM       Prompts per repository state [default=5]'
  print -r -- '  -f, --fixture-files NUM    Tracked files in the fixture [default=1000]'
  print -r -- '      --settle-ms NUM        Quiet period after output [default=150]'
  print -r -- '      --samples-output FILE  Write every timed iteration as long-form TSV'
  print -r -- '      --telemetry-output FILE  Write per-target load and CPU-pressure snapshots'
  print -r -- '      --target NAME          Run one target; may be repeated'
  print -r -- '      --omz DIR              Full OMZ checkout [default=$ZSH or ~/.oh-my-zsh]'
  print -r -- '      --omz-commit SHA       Immutable OMZ source commit'
  print -r -- '      --wakamex DIR          Wakamex checkout [default=../wakamex-zsh-theme]'
  print -r -- '      --pure DIR             Pure checkout [default=../pure]'
  print -r -- '      --pure-commit SHA      Immutable Pure source commit'
  print -r -- '      --powerlevel10k DIR    Powerlevel10k checkout [default=../powerlevel10k]'
  print -r -- '      --powerlevel10k-commit SHA  Immutable Powerlevel10k source commit'
  print -r -- '      --powerlevel10k-gitstatusd FILE  Pinned gitstatusd executable'
  print -r -- '  -s, --scratch-parent DIR   Temporary run parent [default=/var/tmp]'
  print -r --
  print -r -- "Core targets: ${(j:, :)valid_targets}"
}

fail() {
  print -u2 -r -- "error: $*"
  return 1
}

while (( $# )); do
  case $1 in
    -h|--help)
      usage
      return 0
      ;;
    -i|--iterations)
      (( $# >= 2 )) || fail "$1 requires a value"
      iterations=$2
      shift 2
      ;;
    -f|--fixture-files)
      (( $# >= 2 )) || fail "$1 requires a value"
      fixture_files=$2
      shift 2
      ;;
    --settle-ms)
      (( $# >= 2 )) || fail "$1 requires a value"
      settle_ms=$2
      shift 2
      ;;
    --samples-output)
      (( $# >= 2 )) || fail "$1 requires a file"
      samples_output=$2
      shift 2
      ;;
    --telemetry-output)
      (( $# >= 2 )) || fail "$1 requires a file"
      telemetry_output=$2
      shift 2
      ;;
    --target)
      (( $# >= 2 )) || fail "$1 requires a value"
      requested_targets+=($2)
      shift 2
      ;;
    --omz)
      (( $# >= 2 )) || fail "$1 requires a directory"
      omz_dir=$2
      shift 2
      ;;
    --omz-commit)
      (( $# >= 2 )) || fail "$1 requires a commit"
      omz_commit=$2
      shift 2
      ;;
    --wakamex)
      (( $# >= 2 )) || fail "$1 requires a directory"
      wakamex_dir=$2
      shift 2
      ;;
    --pure)
      (( $# >= 2 )) || fail "$1 requires a directory"
      pure_dir=$2
      shift 2
      ;;
    --pure-commit)
      (( $# >= 2 )) || fail "$1 requires a commit"
      pure_commit=$2
      shift 2
      ;;
    --powerlevel10k)
      (( $# >= 2 )) || fail "$1 requires a directory"
      powerlevel10k_dir=$2
      shift 2
      ;;
    --powerlevel10k-commit)
      (( $# >= 2 )) || fail "$1 requires a commit"
      powerlevel10k_commit=$2
      shift 2
      ;;
    --powerlevel10k-gitstatusd)
      (( $# >= 2 )) || fail "$1 requires an executable"
      powerlevel10k_gitstatusd=$2
      shift 2
      ;;
    -s|--scratch-parent)
      (( $# >= 2 )) || fail "$1 requires a directory"
      scratch_parent=$2
      shift 2
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ $iterations == <1-> ]] || fail 'iterations must be a positive integer'
[[ $fixture_files == <1-> ]] || fail 'fixture-files must be a positive integer'
[[ $settle_ms == <1-> ]] || fail 'settle-ms must be a positive integer'
(( ${#requested_targets} )) && targets=("$requested_targets[@]")

local target
for target in $targets; do
  case $target in
    direct-git|raw|wakamex|robbyrussell|agnoster|bureau|Soliah|steeef|apple|mortalscumbag|ys|bira|pure|powerlevel10k-pure|powerlevel10k-fallback) ;;
    *) fail "unknown target: $target" ;;
  esac
done

omz_dir=${omz_dir:A}
wakamex_dir=${wakamex_dir:A}
pure_dir=${pure_dir:A}
powerlevel10k_dir=${powerlevel10k_dir:A}
[[ -z $powerlevel10k_gitstatusd ]] || powerlevel10k_gitstatusd=${powerlevel10k_gitstatusd:A}
scratch_parent=${scratch_parent:A}
[[ -z $samples_output ]] || samples_output=${samples_output:A}
[[ -z $telemetry_output ]] || telemetry_output=${telemetry_output:A}
[[ -d $omz_dir/.git ]] || fail "not an OMZ checkout: $omz_dir"
[[ -r $wakamex_dir/wakamex.zsh-theme ]] || fail "Wakamex theme not found: $wakamex_dir"
local -i needs_pure=$(( ${targets[(Ie)pure]} > 0 ))
local -i needs_powerlevel10k=$(( ${targets[(Ie)powerlevel10k-pure]} > 0 || ${targets[(Ie)powerlevel10k-fallback]} > 0 ))
if (( needs_pure )); then
  [[ -d $pure_dir/.git ]] || fail "not a Pure checkout: $pure_dir"
  command git -C "$pure_dir" cat-file -e "${pure_commit}^{commit}" 2>/dev/null \
    || fail "Pure commit is unavailable: $pure_commit"
fi
if (( needs_powerlevel10k )); then
  [[ -d $powerlevel10k_dir/.git ]] || fail "not a Powerlevel10k checkout: $powerlevel10k_dir"
  command git -C "$powerlevel10k_dir" cat-file -e "${powerlevel10k_commit}^{commit}" 2>/dev/null \
    || fail "Powerlevel10k commit is unavailable: $powerlevel10k_commit"
  if [[ -z $powerlevel10k_gitstatusd ]]; then
    local -a gitstatusd_candidates=("$powerlevel10k_dir"/gitstatus/usrbin/gitstatusd-*(N))
    (( ${#gitstatusd_candidates} == 1 )) \
      || fail 'could not infer gitstatusd; install it in the Powerlevel10k checkout or pass --powerlevel10k-gitstatusd'
    powerlevel10k_gitstatusd=${gitstatusd_candidates[1]:A}
  fi
  [[ -x $powerlevel10k_gitstatusd ]] \
    || fail "Powerlevel10k gitstatusd is not executable: $powerlevel10k_gitstatusd"
fi
[[ -d $scratch_parent && -w $scratch_parent ]] || fail "scratch parent is not writable: $scratch_parent"
if [[ -n $samples_output ]]; then
  [[ -d $samples_output:h && -w $samples_output:h ]] \
    || fail "sample output parent is not writable: $samples_output:h"
  [[ ! -d $samples_output ]] || fail "sample output is a directory: $samples_output"
  [[ -r /proc/pressure/cpu ]] \
    || fail 'sample PSI counters require readable /proc/pressure/cpu'
fi
if [[ -n $telemetry_output ]]; then
  [[ -d $telemetry_output:h && -w $telemetry_output:h ]] \
    || fail "telemetry output parent is not writable: $telemetry_output:h"
  [[ ! -d $telemetry_output ]] || fail "telemetry output is a directory: $telemetry_output"
  [[ -r /proc/loadavg && -r /proc/pressure/cpu ]] \
    || fail 'telemetry requires readable /proc/loadavg and /proc/pressure/cpu'
fi
command git -C "$omz_dir" cat-file -e "${omz_commit}^{commit}" 2>/dev/null \
  || fail "OMZ commit is unavailable: $omz_commit"

local scratch
scratch=$(mktemp -d "$scratch_parent/zsh-theme-core.XXXXXX")
[[ -n $scratch && -d $scratch ]] || fail 'failed to create scratch directory'

local current_pty=
local -i current_pty_fd=-1
local samples_tmp= telemetry_tmp=
cleanup() {
  [[ -n $current_pty ]] && zpty -d "$current_pty" 2>/dev/null || true
  [[ -n $samples_tmp ]] && command rm -f -- "$samples_tmp"
  [[ -n $telemetry_tmp ]] && command rm -f -- "$telemetry_tmp"
  command rm -rf -- "$scratch"
}
trap cleanup EXIT INT TERM

local omz_archive=$scratch/omz
command mkdir "$omz_archive"
command git -C "$omz_dir" archive "$omz_commit" | command tar -x -C "$omz_archive"

local pure_archive= powerlevel10k_archive= powerlevel10k_gitstatusd_sha256=
if (( needs_pure )); then
  pure_archive=$scratch/pure
  command mkdir "$pure_archive"
  command git -C "$pure_dir" archive "$pure_commit" | command tar -x -C "$pure_archive"
fi
if (( needs_powerlevel10k )); then
  powerlevel10k_archive=$scratch/powerlevel10k
  command mkdir "$powerlevel10k_archive"
  command git -C "$powerlevel10k_dir" archive "$powerlevel10k_commit" | command tar -x -C "$powerlevel10k_archive"
  local gitstatus_kernel gitstatus_arch expected_gitstatus_version actual_gitstatus_version
  gitstatus_kernel=$(command uname -s)
  gitstatus_kernel=${gitstatus_kernel:l}
  gitstatus_arch=$(command uname -m)
  gitstatus_arch=${gitstatus_arch:l}
  expected_gitstatus_version=$(command awk \
    -v kernel="$gitstatus_kernel" \
    -v arch="$gitstatus_arch" '
      index($0, "uname_s_glob=\"" kernel "\"") && index($0, "uname_m_glob=\"" arch "\"") {
        if (match($0, /version="[^"]+"/)) {
          value = substr($0, RSTART + 9, RLENGTH - 10)
          print value
          exit
        }
      }
    ' "$powerlevel10k_archive/gitstatus/install.info")
  [[ -n $expected_gitstatus_version ]] \
    || fail "Powerlevel10k has no gitstatusd manifest entry for $gitstatus_kernel/$gitstatus_arch"
  actual_gitstatus_version=$("$powerlevel10k_gitstatusd" --version 2>/dev/null | command awk 'NR == 1 { print; exit }') \
    || fail 'could not query Powerlevel10k gitstatusd version'
  [[ $actual_gitstatus_version == $expected_gitstatus_version ]] \
    || fail "Powerlevel10k gitstatusd is $actual_gitstatus_version; expected $expected_gitstatus_version"
  powerlevel10k_gitstatusd_sha256=$(command sha256sum "$powerlevel10k_gitstatusd" | command awk '{print $1}')
  [[ $powerlevel10k_gitstatusd_sha256 == [0-9a-f](#c64) ]] \
    || fail 'could not hash Powerlevel10k gitstatusd'
  command mkdir -p "$powerlevel10k_archive/gitstatus/usrbin"
  command cp -- "$powerlevel10k_gitstatusd" "$powerlevel10k_archive/gitstatus/usrbin/gitstatusd"
  command chmod 755 "$powerlevel10k_archive/gitstatus/usrbin/gitstatusd"
fi

local fixture=$scratch/fixture
local remote=$scratch/remote.git
command git init -q -b main "$fixture"
command git -C "$fixture" config user.name zsh-theme-bench
command git -C "$fixture" config user.email zsh-theme-bench@example.invalid

local -i file_number
for (( file_number = 1; file_number <= fixture_files; ++file_number )); do
  print -r -- seed > "$fixture/file-$file_number"
done
command git -C "$fixture" add .
command git -C "$fixture" commit -qm seed
local fixture_head_short
fixture_head_short=$(command git -C "$fixture" rev-parse --short=7 HEAD)
command git init -q --bare "$remote"
command git -C "$fixture" remote add origin "$remote"
command git -C "$fixture" push -qu origin main

local probe_bin=$scratch/bin
local git_log=$scratch/git-environment.log
local git_activity_log=$scratch/git-activity.log
local real_git=${commands[git]:A}
command mkdir "$probe_bin"
command ln -s "$root/internal/git-probe" "$probe_bin/git"
: > "$git_log"
: > "$git_activity_log"

source "$root/internal/stats.zsh"

typeset -g pty_output=
typeset -g prompt_marker='ZTB_PROMPT>'
typeset -gF measured_first_ms=0
typeset -gF measured_settled_ms=0
typeset -gi measured_repaints=0
typeset -g semantic_output=
typeset -g cpu_psi_some_avg10=
typeset -g cpu_psi_some_avg60=
typeset -g cpu_psi_some_avg300=
typeset -g cpu_psi_some_total=

read_cpu_psi_some() {
  local pressure_line
  local -a pressure_fields

  IFS= read -r pressure_line < /proc/pressure/cpu
  pressure_fields=(${=pressure_line})
  (( ${#pressure_fields} >= 5 )) || fail 'could not parse CPU pressure telemetry'
  [[ $pressure_fields[1] == some \
    && $pressure_fields[2] == avg10=* \
    && $pressure_fields[3] == avg60=* \
    && $pressure_fields[4] == avg300=* \
    && $pressure_fields[5] == total=* ]] \
    || fail 'unexpected /proc/pressure/cpu format'

  cpu_psi_some_avg10=${pressure_fields[2]#avg10=}
  cpu_psi_some_avg60=${pressure_fields[3]#avg60=}
  cpu_psi_some_avg300=${pressure_fields[4]#avg300=}
  cpu_psi_some_total=${pressure_fields[5]#total=}
}

pty_read_available() {
  local chunk
  while zpty -r -t "$current_pty" chunk 2>/dev/null; do
    pty_output+=$chunk
  done
  return 0
}

pty_wait_for() {
  local expected=$1
  local -F timeout=${2:-5}
  local -F deadline=$(( EPOCHREALTIME + timeout ))

  while (( EPOCHREALTIME < deadline )); do
    pty_read_available
    [[ $pty_output == *$expected* ]] && return 0
    zselect -r "$current_pty_fd" -t 1 2>/dev/null || true
  done

  pty_read_available
  print -u2 -r -- "PTY timeout waiting for ${(qqq)expected}"
  return 1
}

marker_count() {
  local without=${pty_output//$prompt_marker/}
  REPLY=$(( (${#pty_output} - ${#without}) / ${#prompt_marker} ))
}

git_activity_count() {
  local -a lines=("${(@f)$(< "$git_activity_log")}")
  if (( ${#lines} == 1 && ! ${#lines[1]} )); then
    REPLY=0
  else
    REPLY=${#lines}
  fi
}

git_activity_busy() {
  local -i start_line=$1 index pid
  local -a lines=("${(@f)$(< "$git_activity_log")}")

  REPLY=0
  for (( index = start_line + 1; index <= ${#lines}; ++index )); do
    pid=${lines[$index]}
    if [[ $pid == <1-> ]] && kill -0 "$pid" 2>/dev/null; then
      REPLY=1
      return 0
    fi
  done
}

pty_measure_prompt() {
  local command_text=$1
  local -F start=$EPOCHREALTIME
  local -F now last_activity=$start first_at=0 last_prompt_at=0
  local -F quiet_seconds=$(( settle_ms / 1000.0 ))
  local -F deadline=$(( start + 15 ))
  local -i count=0 previous_count=0
  local -i activity_start previous_activity_count current_activity_count activity_busy
  local chunk

  pty_output=
  git_activity_count
  activity_start=$REPLY
  previous_activity_count=$activity_start
  zpty -w "$current_pty" "$command_text"

  while (( EPOCHREALTIME < deadline )); do
    while zpty -r -t "$current_pty" chunk 2>/dev/null; do
      pty_output+=$chunk
      now=$EPOCHREALTIME
      last_activity=$now

      marker_count
      count=$REPLY
      if (( count > previous_count )); then
        (( previous_count == 0 )) && first_at=$now
        last_prompt_at=$now
        previous_count=$count
      fi
    done

    now=$EPOCHREALTIME

    git_activity_count
    current_activity_count=$REPLY
    if (( current_activity_count != previous_activity_count )); then
      last_activity=$now
      previous_activity_count=$current_activity_count
    fi
    git_activity_busy "$activity_start"
    activity_busy=$REPLY

    if (( previous_count > 0 && ! activity_busy && now - last_activity >= quiet_seconds )); then
      measured_first_ms=$(( (first_at - start) * 1000 ))
      measured_settled_ms=$(( (last_prompt_at - start) * 1000 ))
      measured_repaints=$(( previous_count - 1 ))
      return 0
    fi

    zselect -r "$current_pty_fd" -t 1 2>/dev/null || true
  done

  print -u2 -r -- "PTY timeout measuring $target: ${(qqq)command_text}"
  return 1
}

pty_capture_semantics() {
  local begin_marker='ZTB_SEMANTIC_BEGIN>'
  local end_marker='<ZTB_SEMANTIC_END'
  local command_text

  command_text="local _ztb_semantic_prompt=\${PROMPT//\$ZTB_MARKER/}; print -rP -- ${(q)begin_marker} \"\${_ztb_semantic_prompt}\${RPROMPT-}\" ${(q)end_marker}"
  pty_measure_prompt "$command_text"
  [[ $pty_output == *$begin_marker*$end_marker* ]] \
    || fail "semantic prompt capture failed for $target"
  semantic_output=${pty_output#*$begin_marker}
  semantic_output=${semantic_output%%$end_marker*}
}

semantic_prompt_matches() {
  local state=$1 output=$2 expected

  case $target:$state in
    wakamex:clean)
      [[ $output == *'±'* && $output != *'!'* && $output != *'?'* ]]
      ;;
    wakamex:dirty)
      [[ $output == *'!'* ]]
      ;;
    wakamex:untracked)
      [[ $output == *'?'* ]]
      ;;
    wakamex:staged)
      [[ $output == *'+'* && $output != *'!'* && $output != *'?'* ]]
      ;;
    wakamex:detached-head)
      [[ $output == *'➦ '* && $output != *main* ]]
      ;;
    robbyrussell:clean|Soliah:clean|ys:clean|bira:clean)
      expected='ZTB_GIT[main:clean]'
      [[ $output == *"$expected"* ]]
      ;;
    robbyrussell:dirty|robbyrussell:untracked|robbyrussell:staged|Soliah:dirty|Soliah:untracked|Soliah:staged|ys:dirty|ys:untracked|ys:staged|bira:dirty|bira:untracked|bira:staged)
      expected='ZTB_GIT[main:dirty]'
      [[ $output == *"$expected"* ]]
      ;;
    robbyrussell:detached-head|ys:detached-head|bira:detached-head)
      expected="ZTB_GIT[${fixture_head_short}:clean]"
      [[ $output == *"$expected"* ]]
      ;;
    Soliah:detached-head)
      [[ $output == *detached-head* && $output != *main* ]]
      ;;
    agnoster:clean)
      [[ $output == *main* && $output == *$'\e[48;5;110m'* ]]
      ;;
    agnoster:dirty|agnoster:untracked)
      [[ $output == *main* && $output == *$'\e[48;5;111m'* ]]
      ;;
    agnoster:staged)
      [[ $output == *main* && $output == *'✚'* && $output == *$'\e[48;5;111m'* ]]
      ;;
    agnoster:detached-head)
      [[ $output == *"$fixture_head_short"* && $output != *main* && $output == *$'\e[48;5;110m'* ]]
      ;;
    bureau:clean)
      expected='ZTB_GIT[main :clean]'
      [[ $output == *"$expected"* ]]
      ;;
    bureau:dirty)
      expected='ZTB_GIT[main :unstaged]'
      [[ $output == *"$expected"* ]]
      ;;
    bureau:untracked)
      expected='ZTB_GIT[main :untracked]'
      [[ $output == *"$expected"* ]]
      ;;
    bureau:staged)
      expected='ZTB_GIT[main :staged]'
      [[ $output == *"$expected"* ]]
      ;;
    bureau:detached-head)
      expected="ZTB_GIT[$fixture_head_short :clean]"
      [[ $output == *"$expected"* ]]
      ;;
    steeef:clean)
      [[ $output == *main* && $output != *':unstaged'* && $output != *'●'* ]]
      ;;
    steeef:dirty)
      [[ $output == *'(main:unstaged)'* ]]
      ;;
    steeef:untracked)
      [[ $output == *main* && $output == *'●'* ]]
      ;;
    steeef:staged)
      [[ $output == *main* && $output == *':staged'* ]]
      ;;
    steeef:detached-head)
      [[ $output == *'heads/main'* && $output != *'(main'* ]]
      ;;
    apple:clean|apple:untracked)
      expected='ZTB_GIT[main]'
      [[ $output == *"$expected"* && $output != *':unstaged'* ]]
      ;;
    apple:dirty)
      expected='ZTB_GIT[main:unstaged]'
      [[ $output == *"$expected"* ]]
      ;;
    apple:staged)
      expected='ZTB_GIT[main:staged]'
      [[ $output == *"$expected"* ]]
      ;;
    apple:detached-head)
      expected='ZTB_GIT[heads/main]'
      [[ $output == *"$expected"* && $output != *'ZTB_GIT[main]'* ]]
      ;;
    mortalscumbag:clean)
      expected='ZTB_GIT[main]'
      [[ $output == *"$expected"* ]]
      ;;
    mortalscumbag:dirty)
      expected='ZTB_GIT[main :unstaged]'
      [[ $output == *"$expected"* ]]
      ;;
    mortalscumbag:untracked)
      expected='ZTB_GIT[main :untracked]'
      [[ $output == *"$expected"* ]]
      ;;
    mortalscumbag:staged)
      expected='ZTB_GIT[main :staged]'
      [[ $output == *"$expected"* ]]
      ;;
    mortalscumbag:detached-head)
      expected="ZTB_GIT[$fixture_head_short]"
      [[ $output == *"$expected"* ]]
      ;;
    pure:clean|powerlevel10k-pure:clean)
      [[ $output == *main* && $output != *'*'* ]]
      ;;
    pure:dirty|pure:untracked|pure:staged|powerlevel10k-pure:dirty|powerlevel10k-pure:untracked|powerlevel10k-pure:staged)
      [[ $output == *main* && $output == *'*'* ]]
      ;;
    pure:detached-head)
      [[ $output == *'heads/main'* ]]
      ;;
    powerlevel10k-pure:detached-head)
      [[ $output == *"@$fixture_head_short"* && $output != *main* ]]
      ;;
    powerlevel10k-fallback:clean)
      [[ $output == *main* && $output != *':staged'* && $output != *':unstaged'* && $output != *':untracked'* ]]
      ;;
    powerlevel10k-fallback:dirty)
      [[ $output == *main* && $output == *':unstaged'* ]]
      ;;
    powerlevel10k-fallback:untracked)
      [[ $output == *main* && $output == *':untracked'* ]]
      ;;
    powerlevel10k-fallback:staged)
      [[ $output == *main* && $output == *':staged'* && $output != *':unstaged'* && $output != *':untracked'* ]]
      ;;
    powerlevel10k-fallback:detached-head)
      [[ $output == *"ZTB_COMMIT@$fixture_head_short"* && $output != *main* ]]
      ;;
    *)
      fail "semantic matcher is unavailable for $target:$state"
      ;;
  esac
}

run_untimed_semantic_scenario() {
  local scenario=$1 scenario_command

  case $scenario in
    staged)
      scenario_command='command git reset --hard --quiet HEAD; command rm -f -- untracked; print -r -- staged >> file-1; command git add file-1'
      ;;
    detached-head)
      scenario_command='command git reset --hard --quiet HEAD; command rm -f -- untracked; command git switch --detach --quiet HEAD'
      ;;
    *)
      fail "unknown untimed semantic scenario: $scenario"
      ;;
  esac

  pty_measure_prompt "$scenario_command"
  pty_capture_semantics
  if semantic_prompt_matches "$scenario" "$semantic_output"; then
    REPLY=1
  else
    REPLY=0
    print -u2 -r -- "semantic mismatch $target $scenario: ${(qqq)semantic_output}"
  fi
}

git_log_count() {
  local -a lines=("${(@f)$(< "$git_log")}")
  if (( ${#lines} == 1 && ! ${#lines[1]} )); then
    REPLY=0
  else
    REPLY=${#lines}
  fi
}

git_log_delta() {
  local -i start_line=$1 end_line=$2 index
  local -a lines=("${(@f)$(< "$git_log")}")
  typeset -gi measured_git_calls=$(( end_line - start_line ))
  typeset -gi measured_unlocked_calls=0

  if [[ -n ${ZTB_DEBUG_GIT:-} ]]; then
    print -u2 -r -- "git-range $target start=$start_line end=$end_line"
  fi

  for (( index = start_line + 1; index <= end_line; ++index )); do
    local lock_value=${lines[$index]%%$'\t'*}
    [[ $lock_value == 0 ]] || (( ++measured_unlocked_calls ))
    if [[ -n ${ZTB_DEBUG_GIT:-} ]]; then
      print -u2 -r -- "git-trace $target ${lines[$index]}"
    fi
  done
}

ztb_core_child() {
  builtin cd -q -- "$fixture"
  export ZDOTDIR=$scratch/zdotdir-$target
  export ZTB_REAL_GIT=$real_git
  export PATH="$probe_bin:$PATH"
  export ZTB_GIT_LOG=$git_log
  export ZTB_GIT_ACTIVITY_LOG=$git_activity_log
  export ZTB_GIT_TRACE_ARGS=1
  export PS1='ZTB_BOOT> '
  export TERM=xterm-256color
  command mkdir -p "$ZDOTDIR"
  command stty -echo
  exec zsh -dfi
}

local snapshot_at_utc
snapshot_at_utc=$(command date -u +%Y-%m-%dT%H:%M:%SZ)
local benchmark_commit
benchmark_commit=$(command git -C "$root" rev-parse HEAD)
local wakamex_commit
wakamex_commit=$(command git -C "$wakamex_dir" rev-parse HEAD 2>/dev/null || print -r -- unknown)
local pure_source_commit= powerlevel10k_source_commit=
(( needs_pure )) && pure_source_commit=$(command git -C "$pure_dir" rev-parse "${pure_commit}^{commit}")
(( needs_powerlevel10k )) && powerlevel10k_source_commit=$(command git -C "$powerlevel10k_dir" rev-parse "${powerlevel10k_commit}^{commit}")
local zsh_version=${ZSH_VERSION}
local git_version
git_version=$(command git --version | command awk '{print $3}')
local runner_sha256
runner_sha256=$(command sha256sum "${0:A}" | command awk '{print $1}')

local sample_header=$'snapshot_at_utc\tbenchmark_commit\trunner_sha256\ttarget\ttarget_kind\ttarget_commit\tomz_commit\tzsh_version\tgit_version\tfixture_files\tsettle_ms\tstate\titeration\tfirst_ms\tsettled_ms\trepaints\tgit_calls\tunlocked_calls\tsemantic_pass\tmeasurement_started_epoch_seconds\tmeasurement_finished_epoch_seconds\tcpu_psi_some_total_before\tcpu_psi_some_total_after'
local -a sample_rows=()
local telemetry_header=$'snapshot_at_utc\tbenchmark_commit\trunner_sha256\ttarget\ttarget_index\tphase\tobserved_epoch_seconds\tload1\tload5\tload15\tcpu_psi_some_avg10\tcpu_psi_some_avg60\tcpu_psi_some_avg300\tcpu_psi_some_total'
local -a telemetry_rows=()

capture_telemetry() {
  [[ -n $telemetry_output ]] || return 0

  local telemetry_target=$1 telemetry_target_index=$2 telemetry_phase=$3
  local observed_epoch_seconds load_line
  local -a load_fields telemetry_row

  printf -v observed_epoch_seconds '%.6f' "$EPOCHREALTIME"
  IFS= read -r load_line < /proc/loadavg
  load_fields=(${=load_line})
  (( ${#load_fields} >= 3 )) \
    || fail 'could not parse host telemetry'
  read_cpu_psi_some

  telemetry_row=(
    "$snapshot_at_utc" "$benchmark_commit" "$runner_sha256" "$telemetry_target"
    "$telemetry_target_index" "$telemetry_phase" "$observed_epoch_seconds"
    "$load_fields[1]" "$load_fields[2]" "$load_fields[3]"
    "$cpu_psi_some_avg10" "$cpu_psi_some_avg60" "$cpu_psi_some_avg300"
    "$cpu_psi_some_total"
  )
  telemetry_rows+=("${(pj:\t:)telemetry_row}")
}

print -r -- $'snapshot_at_utc\tbenchmark_commit\ttarget\ttarget_kind\ttarget_commit\tomz_commit\tzsh_version\tgit_version\titerations\tfixture_files\tsettle_ms\tload_first_ms\tload_settled_ms\tload_repaints\tload_git_calls\tload_unlocked_calls\tclean_first_ms\tclean_settled_ms\tclean_repaints\tclean_git_calls\tclean_unlocked_calls\tclean_semantic_passes\tdirty_first_ms\tdirty_settled_ms\tdirty_repaints\tdirty_git_calls\tdirty_unlocked_calls\tdirty_semantic_passes\tuntracked_first_ms\tuntracked_settled_ms\tuntracked_repaints\tuntracked_git_calls\tuntracked_unlocked_calls\tuntracked_semantic_passes\tstaged_semantic_pass\tdetached_head_semantic_pass'

local -i target_index=0 target_total=${#targets}
for target in $targets; do
  (( ++target_index ))
  print -u2 -r -- "${target_index}/${target_total} $target load"
  capture_telemetry "$target" "$target_index" start

  command git -C "$fixture" restore .
  command rm -f -- "$fixture/untracked"

  current_pty="zsh_theme_core_${target_index}"
  pty_output=
  zpty -b "$current_pty" ztb_core_child
  current_pty_fd=$REPLY
  pty_wait_for 'ZTB_BOOT>' 5

  local target_kind target_commit setup_command semantic_setup=
  case $target in
    raw)
      target_kind=control
      target_commit=$zsh_version
      setup_command="typeset -g ZTB_MARKER=\$'ZTB_\\x50ROMPT>'; PROMPT=\"\${ZTB_MARKER} \"; RPROMPT=; print -r -- ZTB_SETUP_DONE"
      ;;
    direct-git)
      target_kind=control
      target_commit=$git_version
      setup_command="typeset -g ZTB_MARKER=\$'ZTB_\\x50ROMPT>'; function _ztb_direct_git_scan { local -x GIT_OPTIONAL_LOCKS=0; command git status --porcelain=v2 --branch --untracked-files=normal --ignore-submodules=dirty >/dev/null 2>&1 }; autoload -Uz add-zsh-hook; add-zsh-hook precmd _ztb_direct_git_scan; PROMPT=\"\${ZTB_MARKER} \"; RPROMPT=; print -r -- ZTB_SETUP_DONE"
      ;;
    wakamex)
      target_kind=local
      target_commit=$wakamex_commit
      setup_command="typeset -g ZTB_MARKER=\$'ZTB_\\x50ROMPT>'; typeset -gA FG FX; FG[071]=; FG[124]=; FG[242]=; FX[bold]=; FX[no-bold]=; FX[reset]=; source ${(q)wakamex_dir}/wakamex.zsh-theme; PROMPT=\"\${PROMPT}\${ZTB_MARKER} \"; print -r -- ZTB_SETUP_DONE"
      ;;
    pure)
      target_kind=external
      target_commit=$pure_source_commit
      setup_command="typeset -g ZTB_MARKER=\$'ZTB_\\x50ROMPT>'; typeset -g PURE_GIT_PULL=0 PURE_GIT_UNTRACKED_DIRTY=1; fpath=(${(q)pure_archive} \$fpath); autoload -Uz promptinit; promptinit; prompt pure; PROMPT=\"\${PROMPT}\${ZTB_MARKER} \"; print -r -- ZTB_SETUP_DONE"
      ;;
    powerlevel10k-pure)
      target_kind=external
      target_commit=$powerlevel10k_source_commit
      setup_command="typeset -g ZTB_MARKER=\$'ZTB_\\x50ROMPT>'; typeset -gx GITSTATUS_DAEMON=${(q)powerlevel10k_archive}/gitstatus/usrbin/gitstatusd; typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true; source ${(q)powerlevel10k_archive}/powerlevel10k.zsh-theme; source ${(q)powerlevel10k_archive}/config/p10k-pure.zsh; function prompt_ztb_marker { p10k segment -t \"\$ZTB_MARKER \" }; POWERLEVEL9K_LEFT_PROMPT_ELEMENTS+=(ztb_marker); p10k reload; print -r -- ZTB_SETUP_DONE"
      ;;
    powerlevel10k-fallback)
      target_kind=external
      target_commit=$powerlevel10k_source_commit
      setup_command="typeset -g ZTB_MARKER=\$'ZTB_\\x50ROMPT>'; typeset -gx GITSTATUS_DAEMON=${(q)powerlevel10k_archive}/gitstatus/usrbin/gitstatusd; typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true; source ${(q)powerlevel10k_archive}/powerlevel10k.zsh-theme; typeset -g POWERLEVEL9K_VCS_BRANCH_ICON='' POWERLEVEL9K_VCS_COMMIT_ICON='ZTB_COMMIT@' POWERLEVEL9K_VCS_DIRTY_ICON='' POWERLEVEL9K_VCS_STAGED_ICON=':staged' POWERLEVEL9K_VCS_UNSTAGED_ICON=':unstaged' POWERLEVEL9K_VCS_UNTRACKED_ICON=':untracked'; typeset -ga POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs ztb_marker); function prompt_ztb_marker { p10k segment -t \"\$ZTB_MARKER \" }; p10k reload; print -r -- ZTB_SETUP_DONE"
      ;;
    *)
      target_kind=omz
      target_commit=$omz_commit
      case $target in
        robbyrussell|Soliah|ys|bira)
          semantic_setup="ZSH_THEME_GIT_PROMPT_PREFIX='ZTB_GIT['; ZSH_THEME_GIT_PROMPT_SUFFIX=']'; ZSH_THEME_GIT_PROMPT_CLEAN=':clean'; ZSH_THEME_GIT_PROMPT_DIRTY=':dirty'"
          ;;
        agnoster)
          semantic_setup='AGNOSTER_GIT_CLEAN_BG=110; AGNOSTER_GIT_DIRTY_BG=111'
          ;;
        bureau)
          semantic_setup="ZSH_THEME_GIT_PROMPT_PREFIX='ZTB_GIT['; ZSH_THEME_GIT_PROMPT_SUFFIX=']'; ZSH_THEME_GIT_PROMPT_CLEAN=':clean'; ZSH_THEME_GIT_PROMPT_STAGED=':staged'; ZSH_THEME_GIT_PROMPT_UNSTAGED=':unstaged'; ZSH_THEME_GIT_PROMPT_UNTRACKED=':untracked'"
          ;;
        steeef)
          semantic_setup="FMT_UNSTAGED=':unstaged'; FMT_STAGED=':staged'; zstyle ':vcs_info:*:prompt:*' unstagedstr \"\$FMT_UNSTAGED\"; zstyle ':vcs_info:*:prompt:*' stagedstr \"\$FMT_STAGED\""
          ;;
        apple)
          semantic_setup="zstyle ':vcs_info:*' unstagedstr ':unstaged'; zstyle ':vcs_info:*' stagedstr ':staged'; zstyle ':vcs_info:*' formats 'ZTB_GIT[%b%c%u]'; zstyle ':vcs_info:*' actionformats 'ZTB_GIT[%b:%a%c%u]'"
          ;;
        mortalscumbag)
          semantic_setup="ZSH_THEME_GIT_PROMPT_PREFIX='ZTB_GIT['; ZSH_THEME_GIT_PROMPT_SUFFIX=']'; ZSH_THEME_GIT_PROMPT_STAGED=':staged'; ZSH_THEME_GIT_PROMPT_UNSTAGED=':unstaged'; ZSH_THEME_GIT_PROMPT_UNTRACKED=':untracked'; ZSH_THEME_GIT_PROMPT_UNMERGED=':unmerged'"
          ;;
      esac
      setup_command="typeset -g ZTB_MARKER=\$'ZTB_\\x50ROMPT>'; ZSH=${(q)omz_archive}; ZSH_THEME=${(q)target}; plugins=(); ZSH_COMPDUMP=${(q)scratch}/zcompdump-${(q)target}; ZSH_CACHE_DIR=${(q)scratch}/cache-${(q)target}; DISABLE_AUTO_UPDATE=true; DISABLE_AUTO_TITLE=true; ZSH_DISABLE_COMPFIX=true; source ${(q)omz_archive}/oh-my-zsh.sh; $semantic_setup; PROMPT=\"\${PROMPT}\${ZTB_MARKER} \"; print -r -- ZTB_SETUP_DONE"
      ;;
  esac

  git_log_count
  local -i log_before=$REPLY
  pty_measure_prompt "$setup_command"
  local load_first_ms=$measured_first_ms
  local load_settled_ms=$measured_settled_ms
  local -i load_repaints=$measured_repaints
  git_log_count
  git_log_delta "$log_before" "$REPLY"
  local -i load_git_calls=$measured_git_calls load_unlocked_calls=$measured_unlocked_calls

  local state state_command state_prep_command
  local -a first_samples settled_samples repaint_samples call_samples unlocked_samples
  local clean_first_ms clean_settled_ms clean_repaints clean_git_calls clean_unlocked_calls
  local dirty_first_ms dirty_settled_ms dirty_repaints dirty_git_calls dirty_unlocked_calls
  local untracked_first_ms untracked_settled_ms untracked_repaints untracked_git_calls untracked_unlocked_calls
  local clean_semantic_passes dirty_semantic_passes untracked_semantic_passes
  local staged_semantic_pass detached_head_semantic_pass
  local -i iteration semantic_passes
  local semantic_pass
  local sample_first_ms sample_settled_ms
  local sample_repaints sample_git_calls sample_unlocked_calls
  local measurement_started_epoch_seconds measurement_finished_epoch_seconds
  local cpu_psi_some_total_before cpu_psi_some_total_after
  local -a sample_row

  for state in clean dirty untracked; do
    print -u2 -r -- "${target_index}/${target_total} $target $state"
    command git -C "$fixture" restore .
    command rm -f -- "$fixture/untracked"
    case $state in
      clean)
        state_prep_command='print -r -- changed >> file-1'
        state_command='print -r -- seed > file-1'
        ;;
      dirty)
        state_prep_command='print -r -- seed > file-1'
        state_command='print -r -- changed >> file-1'
        ;;
      untracked)
        state_prep_command='print -r -- seed > file-1; command rm -f -- untracked'
        state_command='print -r -- untracked > untracked'
        ;;
    esac

    first_samples=()
    settled_samples=()
    repaint_samples=()
    call_samples=()
    unlocked_samples=()
    semantic_passes=0

    for (( iteration = 1; iteration <= iterations; ++iteration )); do
      pty_measure_prompt "$state_prep_command"
      git_log_count
      log_before=$REPLY
      measurement_started_epoch_seconds=na
      measurement_finished_epoch_seconds=na
      cpu_psi_some_total_before=na
      cpu_psi_some_total_after=na
      if [[ -n $samples_output ]]; then
        printf -v measurement_started_epoch_seconds '%.6f' "$EPOCHREALTIME"
        read_cpu_psi_some
        cpu_psi_some_total_before=$cpu_psi_some_total
      fi
      pty_measure_prompt "$state_command"
      if [[ -n $samples_output ]]; then
        read_cpu_psi_some
        cpu_psi_some_total_after=$cpu_psi_some_total
        printf -v measurement_finished_epoch_seconds '%.6f' "$EPOCHREALTIME"
      fi
      git_log_count
      git_log_delta "$log_before" "$REPLY"

      first_samples+=("$measured_first_ms")
      settled_samples+=("$measured_settled_ms")
      repaint_samples+=("$measured_repaints")
      call_samples+=("$measured_git_calls")
      unlocked_samples+=("$measured_unlocked_calls")
      printf -v sample_first_ms '%.3f' "$measured_first_ms"
      printf -v sample_settled_ms '%.3f' "$measured_settled_ms"
      sample_repaints=$measured_repaints
      sample_git_calls=$measured_git_calls
      sample_unlocked_calls=$measured_unlocked_calls

      semantic_pass=na
      if [[ $target_kind != control ]]; then
        pty_capture_semantics
        if semantic_prompt_matches "$state" "$semantic_output"; then
          semantic_pass=1
          (( ++semantic_passes ))
        else
          semantic_pass=0
          if (( iteration == 1 )); then
            print -u2 -r -- "semantic mismatch $target $state: ${(qqq)semantic_output}"
          fi
        fi
      fi

      sample_row=(
        "$snapshot_at_utc" "$benchmark_commit" "$runner_sha256" "$target" "$target_kind"
        "$target_commit" "$omz_commit" "$zsh_version" "$git_version" "$fixture_files"
        "$settle_ms" "$state" "$iteration" "$sample_first_ms" "$sample_settled_ms"
        "$sample_repaints" "$sample_git_calls" "$sample_unlocked_calls" "$semantic_pass"
        "$measurement_started_epoch_seconds" "$measurement_finished_epoch_seconds"
        "$cpu_psi_some_total_before" "$cpu_psi_some_total_after"
      )
      sample_rows+=("${(pj:\t:)sample_row}")
    done

    ztb_median "${first_samples[@]}"
    typeset "${state}_first_ms=$REPLY"
    ztb_median "${settled_samples[@]}"
    typeset "${state}_settled_ms=$REPLY"
    ztb_median "${repaint_samples[@]}"
    typeset "${state}_repaints=$REPLY"
    ztb_median "${call_samples[@]}"
    typeset "${state}_git_calls=$REPLY"
    ztb_median "${unlocked_samples[@]}"
    typeset "${state}_unlocked_calls=$REPLY"
    if [[ $target_kind == control ]]; then
      typeset "${state}_semantic_passes=na"
    else
      typeset "${state}_semantic_passes=$semantic_passes"
    fi
  done

  if [[ $target_kind == control ]]; then
    staged_semantic_pass=na
    detached_head_semantic_pass=na
  else
    print -u2 -r -- "${target_index}/${target_total} $target staged semantics"
    run_untimed_semantic_scenario staged
    staged_semantic_pass=$REPLY
    print -u2 -r -- "${target_index}/${target_total} $target detached-head semantics"
    run_untimed_semantic_scenario detached-head
    detached_head_semantic_pass=$REPLY
  fi

  zpty -w "$current_pty" exit 2>/dev/null || true
  zpty -d "$current_pty" 2>/dev/null || true
  current_pty=
  current_pty_fd=-1
  command git -C "$fixture" switch --quiet main
  command git -C "$fixture" reset --hard --quiet HEAD
  command rm -f -- "$fixture/untracked"
  capture_telemetry "$target" "$target_index" end

  local -a result_row=(
    "$snapshot_at_utc" "$benchmark_commit" "$target" "$target_kind" "$target_commit"
    "$omz_commit" "$zsh_version" "$git_version" "$iterations" "$fixture_files" "$settle_ms"
    "$load_first_ms" "$load_settled_ms" "$load_repaints" "$load_git_calls" "$load_unlocked_calls"
    "$clean_first_ms" "$clean_settled_ms" "$clean_repaints" "$clean_git_calls" "$clean_unlocked_calls" "$clean_semantic_passes"
    "$dirty_first_ms" "$dirty_settled_ms" "$dirty_repaints" "$dirty_git_calls" "$dirty_unlocked_calls" "$dirty_semantic_passes"
    "$untracked_first_ms" "$untracked_settled_ms" "$untracked_repaints" "$untracked_git_calls" "$untracked_unlocked_calls" "$untracked_semantic_passes"
    "$staged_semantic_pass" "$detached_head_semantic_pass"
  )
  printf '%s' "$result_row[1]"
  printf '\t%s' "${result_row[@]:1}"
  printf '\n'
done

if [[ -n $samples_output ]]; then
  samples_tmp=$(command mktemp "$samples_output:h/.${samples_output:t}.XXXXXX")
  {
    print -r -- "$sample_header"
    print -r -l -- "$sample_rows[@]"
  } > "$samples_tmp"
  command mv -f -- "$samples_tmp" "$samples_output"
  samples_tmp=
fi

if [[ -n $telemetry_output ]]; then
  telemetry_tmp=$(command mktemp "$telemetry_output:h/.${telemetry_output:t}.XXXXXX")
  {
    print -r -- "$telemetry_header"
    print -r -l -- "$telemetry_rows[@]"
  } > "$telemetry_tmp"
  command mv -f -- "$telemetry_tmp" "$telemetry_output"
  telemetry_tmp=
fi
