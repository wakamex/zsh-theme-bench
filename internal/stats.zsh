#!/usr/bin/env zsh

ztb_median() {
  local -a sorted
  sorted=("${(@f)$(printf '%s\n' "$@" | LC_ALL=C sort -n)}")
  local -i count=${#sorted}

  if (( count % 2 )); then
    REPLY=$sorted[$(( count / 2 + 1 ))]
  else
    REPLY=$(( (sorted[count / 2] + sorted[count / 2 + 1]) / 2.0 ))
  fi
  printf -v REPLY '%.3f' "$REPLY"
}

ztb_measure() {
  local metric_name=$1
  local measured_function=$2
  local -i iterations=$3 iteration
  local -a samples=()
  local -F start elapsed

  for (( iteration = 1; iteration <= iterations; ++iteration )); do
    start=$EPOCHREALTIME
    "$measured_function"
    elapsed=$(( (EPOCHREALTIME - start) * 1000 ))
    samples+=("$elapsed")
  done

  ztb_median "${samples[@]}"
}
