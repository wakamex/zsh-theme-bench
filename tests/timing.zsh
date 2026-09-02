#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail
setopt typeset_silent
zmodload zsh/datetime zsh/zpty zsh/zselect

local -i iterations=3
local -F observer_limit_ms=2.0
local output_format=human
local option_value

usage() {
  print -r -- 'usage: timing.zsh [--iterations N] [--max-observer-error-ms NUM] [--tsv]'
}

while (( $# )); do
  case $1 in
    --iterations)
      (( $# >= 2 )) || {
        print -u2 -r -- '--iterations requires a value'
        return 1
      }
      option_value=$2
      [[ $option_value == <1-> ]] || {
        print -u2 -r -- 'iterations must be a positive integer'
        return 1
      }
      iterations=$option_value
      shift 2
      ;;
    --max-observer-error-ms)
      (( $# >= 2 )) || {
        print -u2 -r -- '--max-observer-error-ms requires a value'
        return 1
      }
      option_value=$2
      [[ $option_value =~ '^[0-9]+([.][0-9]+)?$' ]] || {
        print -u2 -r -- 'max observer error must be a positive number'
        return 1
      }
      observer_limit_ms=$option_value
      shift 2
      ;;
    --tsv)
      output_format=tsv
      shift
      ;;
    -h|--help)
      usage
      return 0
      ;;
    *)
      print -u2 -r -- "unknown option: $1"
      return 1
      ;;
  esac
done

[[ $iterations == <1-> ]] || {
  print -u2 -r -- 'iterations must be a positive integer'
  return 1
}
(( observer_limit_ms > 0 )) || {
  print -u2 -r -- 'max observer error must be positive'
  return 1
}

local pty_name=zsh_theme_bench_timing
local -i pty_fd=-1

cleanup() {
  zpty -d "$pty_name" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

timing_child() {
  command stty -echo
  print -r -- READY

  local delay
  local -F started deadline emitted
  while IFS= read -r delay; do
    started=$EPOCHREALTIME
    deadline=$(( started + delay ))
    while (( EPOCHREALTIME < deadline )); do
      :
    done
    emitted=$EPOCHREALTIME
    printf 'EVENT\t%.9f\t%.9f\n' "$started" "$emitted"
  done
}

zpty -b "$pty_name" timing_child
pty_fd=$REPLY
zselect -r "$pty_fd" -t 100
local ready
zpty -r -t "$pty_name" ready
ready=${ready//$'\r'/}
ready=${ready//$'\n'/}
[[ $ready == READY ]] || {
  print -u2 -r -- "timing calibration failed to start: ${(qqq)ready}"
  return 1
}

local -a delays_ms=(5 20 50)
local -a observer_error_samples=()
local -i delay_ms iteration
local delay_seconds line event rest
local -F detected started emitted actual_ms delay_error_ms observer_error_ms
local -F max_delay_error_ms=0 max_observer_error_ms=0

percentile() {
  local -i percentage=$1
  shift
  local -a sorted
  sorted=("${(@f)$(printf '%s\n' "$@" | LC_ALL=C command sort -n)}")
  local -i count=${#sorted}
  local -i rank=$(( (percentage * count + 99) / 100 ))
  REPLY=$sorted[$rank]
  printf -v REPLY '%.3f' "$REPLY"
}

for delay_ms in $delays_ms; do
  delay_seconds=$(( delay_ms / 1000.0 ))
  for (( iteration = 1; iteration <= iterations; ++iteration )); do
    zpty -w "$pty_name" "$delay_seconds"
    zselect -r "$pty_fd" -t 100 || {
      print -u2 -r -- "timing calibration timed out for ${delay_ms} ms"
      return 1
    }
    zpty -r -t "$pty_name" line || {
      print -u2 -r -- "timing calibration produced no event for ${delay_ms} ms"
      return 1
    }
    detected=$EPOCHREALTIME
    line=${line//$'\r'/}
    line=${line//$'\n'/}
    event=${line%%$'\t'*}
    rest=${line#*$'\t'}
    started=${rest%%$'\t'*}
    emitted=${rest#*$'\t'}
    [[ $event == EVENT && $started == <->.<-> && $emitted == <->.<-> ]] || {
      print -u2 -r -- "invalid timing calibration event: ${(qqq)line}"
      return 1
    }

    actual_ms=$(( (emitted - started) * 1000 ))
    delay_error_ms=$(( actual_ms - delay_ms ))
    (( delay_error_ms < 0 )) && delay_error_ms=$(( -delay_error_ms ))
    observer_error_ms=$(( (detected - emitted) * 1000 ))
    (( delay_error_ms > max_delay_error_ms )) && max_delay_error_ms=$delay_error_ms
    (( observer_error_ms > max_observer_error_ms )) && max_observer_error_ms=$observer_error_ms
    observer_error_samples+=("$observer_error_ms")

    (( delay_error_ms <= 10.0 )) || {
      print -u2 -r -- "${delay_ms} ms calibration delay missed by ${delay_error_ms} ms"
      return 1
    }
    (( observer_error_ms >= -0.1 && observer_error_ms <= observer_limit_ms )) || {
      print -u2 -r -- "PTY observer error was ${observer_error_ms} ms for ${delay_ms} ms calibration; limit is ${observer_limit_ms} ms"
      return 1
    }
  done
done

local median_observer_error_ms p90_observer_error_ms
percentile 50 "$observer_error_samples[@]"
median_observer_error_ms=$REPLY
percentile 90 "$observer_error_samples[@]"
p90_observer_error_ms=$REPLY

if [[ $output_format == tsv ]]; then
  printf '%.3f\t%s\t%s\t%.3f\n' \
    "$max_delay_error_ms" "$median_observer_error_ms" \
    "$p90_observer_error_ms" "$max_observer_error_ms"
else
  printf 'PASS: PTY timing calibration, max delay error %.3f ms, median observer error %s ms, p90 observer error %s ms, max observer error %.3f ms\n' \
    "$max_delay_error_ms" "$median_observer_error_ms" \
    "$p90_observer_error_ms" "$max_observer_error_ms"
fi
