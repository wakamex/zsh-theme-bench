#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail -o extended_glob
setopt typeset_silent

local root=${0:A:h:h}
local timing_script=$root/tests/timing.zsh
local benchmark_script=$root/research/benchmark-core-themes.zsh
local output=
local -i calibration_iterations=10
local -F observer_p90_limit_ms=0.5
local -F observer_max_limit_ms=5.0
local -F cpu_psi_median_limit_percent=5.0
local -i allow_dirty=0
local -a benchmark_args=()
local option_value

usage() {
  print -r -- 'usage: run-core-theme-benchmark.zsh --output DIR [OPTION].. [-- BENCHMARK_OPTION]..'
  print -r --
  print -r -- 'Run timing calibration before and after the core matrix, then atomically publish:'
  print -r -- '  summary.tsv   Median values from the core benchmark'
  print -r -- '  samples.tsv   Every timed iteration in long-form TSV'
  print -r -- '  telemetry.tsv Per-target start/end load and Linux CPU-pressure snapshots'
  print -r -- '  metadata.txt  Calibration, provenance, hashes, and run configuration'
  print -r --
  print -r -- 'OPTIONS'
  print -r -- '  -h, --help'
  print -r -- '  -o, --output DIR                  New destination directory'
  print -r -- '      --calibration-iterations NUM  Events per 5, 20, and 50 ms delay [default=10]'
  print -r -- '      --p90-observer-error-ms NUM   Reject larger p90 PTY read error [default=0.5]'
  print -r -- '      --max-observer-error-ms NUM   Reject any larger PTY read error [default=5]'
  print -r -- '      --max-median-cpu-psi-percent NUM  Reject larger median sample PSI overlap [default=5]'
  print -r -- '      --allow-dirty                 Permit tracked working-tree changes'
  print -r -- '      --                             Pass remaining options to benchmark-core-themes.zsh'
  print -r -- '  Published runs use 20 benchmark iterations unless overridden after --.'
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
    -o|--output)
      (( $# >= 2 )) || fail "$1 requires a directory"
      output=$2
      shift 2
      ;;
    --calibration-iterations)
      (( $# >= 2 )) || fail "$1 requires a value"
      option_value=$2
      [[ $option_value == <1-> ]] || fail 'calibration iterations must be a positive integer'
      calibration_iterations=$option_value
      shift 2
      ;;
    --p90-observer-error-ms)
      (( $# >= 2 )) || fail "$1 requires a value"
      option_value=$2
      [[ $option_value =~ '^[0-9]+([.][0-9]+)?$' ]] \
        || fail 'p90 observer error must be a positive number'
      observer_p90_limit_ms=$option_value
      shift 2
      ;;
    --max-observer-error-ms)
      (( $# >= 2 )) || fail "$1 requires a value"
      option_value=$2
      [[ $option_value =~ '^[0-9]+([.][0-9]+)?$' ]] \
        || fail 'max observer error must be a positive number'
      observer_max_limit_ms=$option_value
      shift 2
      ;;
    --max-median-cpu-psi-percent)
      (( $# >= 2 )) || fail "$1 requires a value"
      option_value=$2
      [[ $option_value =~ '^[0-9]+([.][0-9]+)?$' ]] \
        || fail 'median CPU PSI limit must be a positive number'
      cpu_psi_median_limit_percent=$option_value
      shift 2
      ;;
    --allow-dirty)
      allow_dirty=1
      shift
      ;;
    --)
      shift
      benchmark_args=("$@")
      break
      ;;
    *)
      fail "unknown wrapper option: $1; put benchmark options after --"
      ;;
  esac
done

[[ -n $output ]] || fail '--output is required'
[[ $calibration_iterations == <1-> ]] || fail 'calibration iterations must be a positive integer'
(( observer_p90_limit_ms > 0 )) || fail 'p90 observer error must be positive'
(( observer_max_limit_ms > observer_p90_limit_ms )) \
  || fail 'max observer error must be greater than the p90 limit'
(( cpu_psi_median_limit_percent > 0 )) || fail 'median CPU PSI limit must be positive'
[[ ${benchmark_args[(Ie)--samples-output]} == 0 ]] \
  || fail '--samples-output is managed by this wrapper'
[[ ${benchmark_args[(Ie)--telemetry-output]} == 0 ]] \
  || fail '--telemetry-output is managed by this wrapper'

local powerlevel10k_dir=${ZTB_POWERLEVEL10K_DIR:-${root:h}/powerlevel10k}
local powerlevel10k_gitstatusd=${ZTB_POWERLEVEL10K_GITSTATUSD:-}
local -i explicit_targets=0 powerlevel10k_requested=0
local -i argument_index
for (( argument_index = 1; argument_index <= ${#benchmark_args}; ++argument_index )); do
  case $benchmark_args[$argument_index] in
    --target)
      (( ++argument_index <= ${#benchmark_args} )) || fail '--target requires a value'
      explicit_targets=1
      [[ $benchmark_args[$argument_index] == powerlevel10k-(pure|fallback) ]] && powerlevel10k_requested=1
      ;;
    --powerlevel10k-gitstatusd)
      (( ++argument_index <= ${#benchmark_args} )) || fail '--powerlevel10k-gitstatusd requires a file'
      powerlevel10k_gitstatusd=$benchmark_args[$argument_index]
      ;;
    --powerlevel10k)
      (( ++argument_index <= ${#benchmark_args} )) || fail '--powerlevel10k requires a directory'
      powerlevel10k_dir=$benchmark_args[$argument_index]
      ;;
  esac
done
(( explicit_targets )) || powerlevel10k_requested=1
local powerlevel10k_gitstatusd_sha256=
if (( powerlevel10k_requested )); then
  powerlevel10k_dir=${powerlevel10k_dir:A}
  if [[ -z $powerlevel10k_gitstatusd ]]; then
    local -a gitstatusd_candidates=("$powerlevel10k_dir"/gitstatus/usrbin/gitstatusd-*(N))
    (( ${#gitstatusd_candidates} == 1 )) \
      || fail 'could not infer gitstatusd; install it in the Powerlevel10k checkout or pass --powerlevel10k-gitstatusd'
    powerlevel10k_gitstatusd=$gitstatusd_candidates[1]
  fi
  powerlevel10k_gitstatusd=${powerlevel10k_gitstatusd:A}
  [[ -x $powerlevel10k_gitstatusd ]] \
    || fail "Powerlevel10k gitstatusd is not executable: $powerlevel10k_gitstatusd"
  powerlevel10k_gitstatusd_sha256=$(command sha256sum "$powerlevel10k_gitstatusd" | command awk '{print $1}')
fi

output=${output:A}
local output_parent=$output:h
local output_name=$output:t
[[ $output_name != . && $output_name != .. ]] || fail 'output must name a new directory'
[[ ! -e $output && ! -L $output ]] || fail "output already exists: $output"

local runner_sha256 wrapper_sha256 timing_sha256
runner_sha256=$(command sha256sum "$benchmark_script" | command awk '{print $1}')
wrapper_sha256=$(command sha256sum "${0:A}" | command awk '{print $1}')
timing_sha256=$(command sha256sum "$timing_script" | command awk '{print $1}')
local worktree_dirty=0
[[ -z $(command git -C "$root" status --porcelain --untracked-files=no) ]] || worktree_dirty=1
(( ! worktree_dirty || allow_dirty )) \
  || fail 'tracked worktree changes are not allowed; commit them or pass --allow-dirty'
command mkdir -p -- "$output_parent"

local staging
staging=$(command mktemp -d "$output_parent/.${output_name}.staging.XXXXXX")
[[ -n $staging && -d $staging ]] || fail 'could not create staging directory'

cleanup() {
  [[ -n $staging && -d $staging ]] && command rm -rf -- "$staging"
}
trap cleanup EXIT INT TERM

local summary=$staging/summary.tsv
local samples=$staging/samples.tsv
local telemetry=$staging/telemetry.tsv
local metadata=$staging/metadata.txt
local calibration
local pre_delay_error_ms pre_median_observer_error_ms pre_p90_observer_error_ms pre_max_observer_error_ms
local post_delay_error_ms post_median_observer_error_ms post_p90_observer_error_ms post_max_observer_error_ms

print -u2 -r -- 'calibration before benchmark'
calibration=$("$timing_script" \
  --iterations "$calibration_iterations" \
  --max-observer-error-ms "$observer_max_limit_ms" \
  --tsv) || fail 'pre-run timing calibration failed'
IFS=$'\t' read -r \
  pre_delay_error_ms pre_median_observer_error_ms \
  pre_p90_observer_error_ms pre_max_observer_error_ms \
  <<< "$calibration"
[[ $pre_delay_error_ms == <->.<-> \
  && $pre_median_observer_error_ms == <->.<-> \
  && $pre_p90_observer_error_ms == <->.<-> \
  && $pre_max_observer_error_ms == <->.<-> ]] \
  || fail "invalid pre-run calibration output: $calibration"
(( pre_p90_observer_error_ms <= observer_p90_limit_ms )) \
  || fail "pre-run p90 observer error was ${pre_p90_observer_error_ms} ms; limit is ${observer_p90_limit_ms} ms"

print -u2 -r -- 'core theme benchmark'
"$benchmark_script" \
  --iterations 20 \
  --samples-output "$samples" \
  --telemetry-output "$telemetry" \
  "$benchmark_args[@]" \
  > "$summary" || fail 'core theme benchmark failed'

print -u2 -r -- 'calibration after benchmark'
calibration=$("$timing_script" \
  --iterations "$calibration_iterations" \
  --max-observer-error-ms "$observer_max_limit_ms" \
  --tsv) || fail 'post-run timing calibration failed'
IFS=$'\t' read -r \
  post_delay_error_ms post_median_observer_error_ms \
  post_p90_observer_error_ms post_max_observer_error_ms \
  <<< "$calibration"
[[ $post_delay_error_ms == <->.<-> \
  && $post_median_observer_error_ms == <->.<-> \
  && $post_p90_observer_error_ms == <->.<-> \
  && $post_max_observer_error_ms == <->.<-> ]] \
  || fail "invalid post-run calibration output: $calibration"
(( post_p90_observer_error_ms <= observer_p90_limit_ms )) \
  || fail "post-run p90 observer error was ${post_p90_observer_error_ms} ms; limit is ${observer_p90_limit_ms} ms"

local summary_header
IFS= read -r summary_header < "$summary"
[[ $summary_header == snapshot_at_utc$'\t'benchmark_commit$'\t'target$'\t'* ]] \
  || fail 'summary TSV has an unexpected header'
local summary_semantic_suffix=$'\tstaged_semantic_pass\tdetached_head_semantic_pass'
[[ $summary_header == *"$summary_semantic_suffix" ]] \
  || fail 'summary TSV lacks untimed semantic scenario fields'

local snapshot_at_utc benchmark_commit first_target target_kind target_commit
local omz_commit zsh_version git_version iterations fixture_files settle_ms remainder
IFS=$'\t' read -r \
  snapshot_at_utc benchmark_commit first_target target_kind target_commit \
  omz_commit zsh_version git_version iterations fixture_files settle_ms remainder \
  < <(command sed -n '2p' "$summary")
[[ -n $snapshot_at_utc && $iterations == <1-> && $fixture_files == <1-> && $settle_ms == <1-> ]] \
  || fail 'summary TSV has no valid data row'

local target_count
target_count=$(command awk 'END { print NR - 1 }' "$summary")
[[ $target_count == <1-> ]] || fail 'summary TSV has no targets'
local actual_untimed_semantic_checks
actual_untimed_semantic_checks=$(command awk -F '\t' '
  NR == 1 { next }
  NF != 36 { exit 2 }
  $4 == "control" {
    if ($35 != "na" || $36 != "na") exit 2
    next
  }
  $35 !~ /^[01]$/ || $36 !~ /^[01]$/ { exit 2 }
  { checks += 2 }
  END { print checks + 0 }
' "$summary") || fail 'summary TSV failed untimed semantic scenario validation'
local expected_sample_count=$(( target_count * iterations * 3 ))

local sample_header=$'snapshot_at_utc\tbenchmark_commit\trunner_sha256\ttarget\ttarget_kind\ttarget_commit\tomz_commit\tzsh_version\tgit_version\tfixture_files\tsettle_ms\tstate\titeration\tfirst_ms\tsettled_ms\trepaints\tgit_calls\tunlocked_calls\tsemantic_pass\tmeasurement_started_epoch_seconds\tmeasurement_finished_epoch_seconds\tcpu_psi_some_total_before\tcpu_psi_some_total_after'
local actual_sample_count
actual_sample_count=$(command awk -F '\t' \
  -v expected_header="$sample_header" \
  -v snapshot="$snapshot_at_utc" \
  -v commit="$benchmark_commit" \
  -v fixture="$fixture_files" \
  -v settle="$settle_ms" '
    NR == 1 {
      if ($0 != expected_header) exit 2
      next
    }
    NF != 23 || $1 != snapshot || $2 != commit || $10 != fixture || $11 != settle ||
        $20 !~ /^[0-9]+[.][0-9]+$/ || $21 !~ /^[0-9]+[.][0-9]+$/ ||
        $22 !~ /^[0-9]+$/ || $23 !~ /^[0-9]+$/ ||
        ($21 + 0) < ($20 + 0) || ($23 + 0) < ($22 + 0) {
      exit 2
    }
    { rows += 1 }
    END { if (!failed) print rows + 0 }
  ' "$samples") || fail 'sample TSV failed schema or provenance validation'
[[ $actual_sample_count == $expected_sample_count ]] \
  || fail "sample TSV has $actual_sample_count rows; expected $expected_sample_count"

local median_sample_cpu_psi_overlap_percent
median_sample_cpu_psi_overlap_percent=$(command gawk -F '\t' '
  NR == 1 { next }
  {
    duration_us = ($21 - $20) * 1000000
    if (duration_us <= 0) exit 2
    overlap[++count] = 100 * ($23 - $22) / duration_us
  }
  END {
    if (!count) exit 2
    asort(overlap)
    middle = int(count / 2)
    median = count % 2 ? overlap[middle + 1] : (overlap[middle] + overlap[middle + 1]) / 2
    printf "%.3f\n", median
  }
' "$samples") || fail 'could not calculate median sample CPU PSI overlap'
(( median_sample_cpu_psi_overlap_percent <= cpu_psi_median_limit_percent )) \
  || fail "median sample CPU PSI overlap was ${median_sample_cpu_psi_overlap_percent}%; limit is ${cpu_psi_median_limit_percent}%"

local telemetry_header=$'snapshot_at_utc\tbenchmark_commit\trunner_sha256\ttarget\ttarget_index\tphase\tobserved_epoch_seconds\tload1\tload5\tload15\tcpu_psi_some_avg10\tcpu_psi_some_avg60\tcpu_psi_some_avg300\tcpu_psi_some_total'
local expected_telemetry_count=$(( target_count * 2 ))
local actual_telemetry_count
actual_telemetry_count=$(command gawk -F '\t' \
  -v expected_header="$telemetry_header" \
  -v snapshot="$snapshot_at_utc" \
  -v commit="$benchmark_commit" '
    ARGIND == 1 && FNR == 1 { next }
    ARGIND == 1 { targets[FNR - 1] = $3; next }
    ARGIND == 2 && FNR == 1 {
      if ($0 != expected_header) exit 2
      next
    }
    ARGIND == 2 {
      row = FNR - 1
      target_index = int((row - 1) / 2) + 1
      expected_phase = row % 2 == 1 ? "start" : "end"
      if (NF != 14 || $1 != snapshot || $2 != commit || $4 != targets[target_index] ||
          $5 != target_index || $6 != expected_phase || $7 !~ /^[0-9]+[.][0-9]+$/ ||
          $8 !~ /^[0-9]+[.][0-9]+$/ || $9 !~ /^[0-9]+[.][0-9]+$/ ||
          $10 !~ /^[0-9]+[.][0-9]+$/ || $11 !~ /^[0-9]+[.][0-9]+$/ ||
          $12 !~ /^[0-9]+[.][0-9]+$/ || $13 !~ /^[0-9]+[.][0-9]+$/ ||
          $14 !~ /^[0-9]+$/) exit 2
      rows += 1
    }
    END { print rows + 0 }
  ' "$summary" "$telemetry") || fail 'telemetry TSV failed schema or provenance validation'
[[ $actual_telemetry_count == $expected_telemetry_count ]] \
  || fail "telemetry TSV has $actual_telemetry_count rows; expected $expected_telemetry_count"

local recorded_runner_sha256 current_runner_sha256 current_wrapper_sha256 current_timing_sha256
recorded_runner_sha256=$(command awk -F '\t' 'NR == 2 { print $3; exit }' "$samples")
[[ $recorded_runner_sha256 == $runner_sha256 ]] \
  || fail 'benchmark source changed while the run was active'
[[ $(command awk -F '\t' 'NR == 2 { print $3; exit }' "$telemetry") == $runner_sha256 ]] \
  || fail 'telemetry recorded an unexpected benchmark source'
current_runner_sha256=$(command sha256sum "$benchmark_script" | command awk '{print $1}')
current_wrapper_sha256=$(command sha256sum "${0:A}" | command awk '{print $1}')
current_timing_sha256=$(command sha256sum "$timing_script" | command awk '{print $1}')
[[ $current_runner_sha256 == $runner_sha256 \
  && $current_wrapper_sha256 == $wrapper_sha256 \
  && $current_timing_sha256 == $timing_sha256 ]] \
  || fail 'benchmark or calibration source changed while the run was active'
if (( powerlevel10k_requested )); then
  [[ $(command sha256sum "$powerlevel10k_gitstatusd" | command awk '{print $1}') == $powerlevel10k_gitstatusd_sha256 ]] \
    || fail 'Powerlevel10k gitstatusd changed while the run was active'
fi
if (( ! allow_dirty )); then
  [[ -z $(command git -C "$root" status --porcelain --untracked-files=no) ]] \
    || fail 'tracked worktree changed while the run was active'
fi

local targets
targets=$(command awk -F '\t' 'NR > 1 { if (seen++) printf ","; printf "%s", $3 } END { print "" }' "$summary")
local pure_commit powerlevel10k_commit
pure_commit=$(command awk -F '\t' '$3 == "pure" { print $5; exit }' "$summary")
powerlevel10k_commit=$(command awk -F '\t' '$3 ~ /^powerlevel10k-(pure|fallback)$/ { print $5; exit }' "$summary")
local summary_sha256 samples_sha256 telemetry_sha256
summary_sha256=$(command sha256sum "$summary" | command awk '{print $1}')
samples_sha256=$(command sha256sum "$samples" | command awk '{print $1}')
telemetry_sha256=$(command sha256sum "$telemetry" | command awk '{print $1}')
local online_cpus
online_cpus=$(command getconf _NPROCESSORS_ONLN)
local accepted_at_utc
accepted_at_utc=$(command date -u +%Y-%m-%dT%H:%M:%SZ)

{
  print -r -- 'format_version=6'
  print -r -- 'accepted=1'
  print -r -- "accepted_at_utc=$accepted_at_utc"
  print -r -- "snapshot_at_utc=$snapshot_at_utc"
  print -r -- "benchmark_commit=$benchmark_commit"
  print -r -- "runner_sha256=$runner_sha256"
  print -r -- "wrapper_sha256=$wrapper_sha256"
  print -r -- "timing_sha256=$timing_sha256"
  print -r -- "worktree_dirty=$worktree_dirty"
  print -r -- "allow_dirty=$allow_dirty"
  print -r -- "omz_commit=$omz_commit"
  [[ -z $pure_commit ]] || print -r -- "pure_commit=$pure_commit"
  if [[ -n $powerlevel10k_commit ]]; then
    print -r -- "powerlevel10k_commit=$powerlevel10k_commit"
    print -r -- "powerlevel10k_gitstatusd_sha256=$powerlevel10k_gitstatusd_sha256"
  fi
  print -r -- "zsh_version=$zsh_version"
  print -r -- "git_version=$git_version"
  print -r -- "online_cpus=$online_cpus"
  print -r -- "targets=$targets"
  print -r -- "iterations=$iterations"
  print -r -- "fixture_files=$fixture_files"
  print -r -- "settle_ms=$settle_ms"
  print -r -- "calibration_iterations=$calibration_iterations"
  printf 'observer_p90_limit_ms=%.3f\n' "$observer_p90_limit_ms"
  printf 'observer_max_limit_ms=%.3f\n' "$observer_max_limit_ms"
  printf 'median_sample_cpu_psi_limit_percent=%.3f\n' "$cpu_psi_median_limit_percent"
  print -r -- "median_sample_cpu_psi_overlap_percent=$median_sample_cpu_psi_overlap_percent"
  print -r -- "pre_calibration_max_delay_error_ms=$pre_delay_error_ms"
  print -r -- "pre_calibration_median_observer_error_ms=$pre_median_observer_error_ms"
  print -r -- "pre_calibration_p90_observer_error_ms=$pre_p90_observer_error_ms"
  print -r -- "pre_calibration_max_observer_error_ms=$pre_max_observer_error_ms"
  print -r -- "post_calibration_max_delay_error_ms=$post_delay_error_ms"
  print -r -- "post_calibration_median_observer_error_ms=$post_median_observer_error_ms"
  print -r -- "post_calibration_p90_observer_error_ms=$post_p90_observer_error_ms"
  print -r -- "post_calibration_max_observer_error_ms=$post_max_observer_error_ms"
  print -r -- "summary_rows=$target_count"
  print -r -- "sample_rows=$actual_sample_count"
  print -r -- "telemetry_rows=$actual_telemetry_count"
  print -r -- 'untimed_semantic_scenarios=staged,detached-head'
  print -r -- "untimed_semantic_checks=$actual_untimed_semantic_checks"
  print -r -- "summary_sha256=$summary_sha256"
  print -r -- "samples_sha256=$samples_sha256"
  print -r -- "telemetry_sha256=$telemetry_sha256"
} > "$metadata"

command mv -T -- "$staging" "$output" || fail "could not publish accepted run: $output"
staging=

print -r -- "accepted_run=$output"
print -r -- "summary=$output/summary.tsv"
print -r -- "samples=$output/samples.tsv"
print -r -- "telemetry=$output/telemetry.tsv"
print -r -- "metadata=$output/metadata.txt"
