#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail

local root=${0:A:h:h}
local output
local test_tmp
test_tmp=$(command mktemp -d /var/tmp/zsh-theme-bench-test.XXXXXX)
[[ -n $test_tmp && -d $test_tmp ]] || return 1

cleanup() {
  command rm -rf -- "$test_tmp"
}
trap cleanup EXIT INT TERM

output=$("$root/zsh-theme-bench" --iterations 2 --fixture-files 20)

local required
for required in \
  cached_prompt_ms git_identity_ms git_status_ms fixture_clean_status_ms \
  fixture_dirty_status_ms fixture_staged_status_ms fixture_untracked_status_ms \
  async_schedule_ms async_ready_ms \
  sync_wait_ms fd_delta check_stderr_preserved check_descriptor_cleanup \
  check_worker_cleanup check_stale_result_ignored check_rapid_prompts_coalesced \
  check_preexec_cancels_worker check_async_repaint check_untracked_detected \
  check_tracked_change_detected check_staged_change_detected check_optional_locks_disabled \
  check_sync_wait_bounded; do
  [[ $output == *$required=* ]] || {
    print -u2 -r -- "missing output field: $required"
    return 1
  }
done

local failed_checks
failed_checks=$(print -r -- "$output" | command grep '^check_.*=0$' || true)
[[ -z $failed_checks ]] || {
  print -u2 -r -- "$failed_checks"
  return 1
}

"$root/zsh-theme-bench" --help >/dev/null
"$root/research/sweep-omz-theme-usage.zsh" --help >/dev/null
"$root/research/collect-omz-theme-metadata.zsh" --help >/dev/null
"$root/research/benchmark-core-themes.zsh" --help >/dev/null
"$root/research/run-core-theme-benchmark.zsh" --help >/dev/null
"$root/research/summarize-core-theme-samples.zsh" --help >/dev/null
"$root/research/validate-core-theme-correctness-assessment.zsh" --help >/dev/null
"$root/research/generate-core-theme-report.zsh" --help >/dev/null
if "$root/zsh-theme-bench" --iterations 0 >/dev/null 2>&1; then
  print -u2 -r -- 'zero iterations unexpectedly succeeded'
  return 1
fi

"$root/tests/timing.zsh"

local comparison
local comparison_samples=$test_tmp/comparison-samples.tsv
local comparison_legacy_samples=$test_tmp/comparison-legacy-samples.tsv
local comparison_telemetry=$test_tmp/comparison-telemetry.tsv
local comparison_summary=$test_tmp/comparison-summary.tsv
local comparison_dispersion=$test_tmp/comparison-dispersion.tsv
comparison=$("$root/research/benchmark-core-themes.zsh" \
  --iterations 1 --fixture-files 20 --settle-ms 20 \
  --samples-output "$comparison_samples" \
  --telemetry-output "$comparison_telemetry")
[[ $comparison == *$'target\ttarget_kind'* && $comparison == *$'\traw\tcontrol\t'* ]] || {
  print -u2 -r -- 'core comparison smoke test returned unexpected output'
  return 1
}
print -r -- "$comparison" > "$comparison_summary"
command awk -F '\t' '
  NR == 1 {
    if (NF != 36 || $35 != "staged_semantic_pass" ||
        $36 != "detached_head_semantic_pass") exit 1
    next
  }
  NF != 36 { exit 1 }
' "$comparison_summary" || {
  print -u2 -r -- 'core comparison summary failed semantic scenario schema validation'
  return 1
}

local semantic_summary
semantic_summary=$(print -r -- "$comparison" | command awk -F '\t' \
  'NR > 1 { print $3 "=" $22 "/" $28 "/" $34 "/" $35 "/" $36 }')
for required in \
  'raw=na/na/na/na/na' \
  'wakamex=1/1/1/1/1' \
  'robbyrussell=1/1/1/1/1' \
  'agnoster=1/1/1/1/1' \
  'bureau=1/1/1/1/1' \
  'Soliah=0/0/0/0/1' \
  'steeef=1/0/0/1/1' \
  'apple=1/1/1/1/1' \
  'mortalscumbag=1/1/1/1/1' \
  'ys=1/1/1/1/1' \
  'bira=1/1/1/1/1' \
  'pure=1/1/1/1/1' \
  'powerlevel10k-pure=1/1/1/1/1' \
  'powerlevel10k-fallback=1/1/1/1/1'; do
  [[ $semantic_summary == *$required* ]] || {
    print -u2 -r -- "missing semantic result: $required"
    print -u2 -r -- "$semantic_summary"
    return 1
  }
done

local direct_control
direct_control=$("$root/research/benchmark-core-themes.zsh" \
  --target raw --target direct-git \
  --iterations 1 --fixture-files 20 --settle-ms 20)
print -r -- "$direct_control" | command awk -F '\t' '
  NR == 1 { next }
  $3 == "raw" {
    if ($4 != "control" || $20 != 0 || $26 != 0 || $32 != 0 ||
        $22 != "na" || $28 != "na" || $34 != "na" || $35 != "na" || $36 != "na") exit 1
    raw += 1
  }
  $3 == "direct-git" {
    if ($4 != "control" || $20 != 1 || $26 != 1 || $32 != 1 ||
        $21 != 0 || $27 != 0 || $33 != 0 ||
        $22 != "na" || $28 != "na" || $34 != "na" || $35 != "na" || $36 != "na") exit 1
    direct += 1
  }
  END { if (raw != 1 || direct != 1) exit 1 }
' || {
  print -u2 -r -- 'direct Git control failed process, lock, or semantic checks'
  return 1
}

command awk -F '\t' '
  NR == 1 {
    if (NF != 23 || $1 != "snapshot_at_utc" || $19 != "semantic_pass" ||
        $20 != "measurement_started_epoch_seconds" ||
        $21 != "measurement_finished_epoch_seconds" ||
        $22 != "cpu_psi_some_total_before" || $23 != "cpu_psi_some_total_after") exit 1
    next
  }
  NF != 23 { exit 1 }
  NR == 2 { runner_sha = $3 }
  $3 != runner_sha { exit 1 }
  $20 !~ /^[0-9]+[.][0-9]+$/ || $21 !~ /^[0-9]+[.][0-9]+$/ ||
      $22 !~ /^[0-9]+$/ || $23 !~ /^[0-9]+$/ ||
      ($21 + 0) < ($20 + 0) || ($23 + 0) < ($22 + 0) { exit 1 }
  { rows += 1 }
  END { if (rows != 42) exit 1 }
' "$comparison_samples" || {
  print -u2 -r -- 'core comparison samples failed schema or row-count validation'
  return 1
}

command awk -F '\t' '
  NR == 1 {
    if (NF != 14 || $1 != "snapshot_at_utc" || $6 != "phase" ||
        $11 != "cpu_psi_some_avg10" || $14 != "cpu_psi_some_total") exit 1
    next
  }
  NF != 14 { exit 1 }
  {
    row = NR - 1
    target_index = int((row - 1) / 2) + 1
    expected_phase = row % 2 == 1 ? "start" : "end"
    if ($5 != target_index || $6 != expected_phase) exit 1
    rows += 1
  }
  END { if (rows != 28) exit 1 }
' "$comparison_telemetry" || {
  print -u2 -r -- 'core comparison telemetry failed schema or row-count validation'
  return 1
}

"$root/research/summarize-core-theme-samples.zsh" \
  "$comparison_samples" > "$comparison_dispersion"
command cut -f 1-19 "$comparison_samples" > "$comparison_legacy_samples"
"$root/research/summarize-core-theme-samples.zsh" \
  "$comparison_legacy_samples" >/dev/null
command gawk -F '\t' '
  ARGIND == 1 && FNR == 1 { next }
  ARGIND == 1 {
    iterations[$3] = $9
    first[$3 SUBSEP "clean"] = $17
    settled[$3 SUBSEP "clean"] = $18
    repaints[$3 SUBSEP "clean"] = $19
    git_calls[$3 SUBSEP "clean"] = $20
    unlocked[$3 SUBSEP "clean"] = $21
    semantics[$3 SUBSEP "clean"] = $22
    first[$3 SUBSEP "dirty"] = $23
    settled[$3 SUBSEP "dirty"] = $24
    repaints[$3 SUBSEP "dirty"] = $25
    git_calls[$3 SUBSEP "dirty"] = $26
    unlocked[$3 SUBSEP "dirty"] = $27
    semantics[$3 SUBSEP "dirty"] = $28
    first[$3 SUBSEP "untracked"] = $29
    settled[$3 SUBSEP "untracked"] = $30
    repaints[$3 SUBSEP "untracked"] = $31
    git_calls[$3 SUBSEP "untracked"] = $32
    unlocked[$3 SUBSEP "untracked"] = $33
    semantics[$3 SUBSEP "untracked"] = $34
    next
  }
  ARGIND == 2 && FNR == 1 { next }
  ARGIND == 2 {
    key = $1 SUBSEP $2
    expected_semantic = semantics[key] == "na" ? "na" : semantics[key] "/" iterations[$1]
    if ($4 != first[key] || $8 != settled[key] || $12 != repaints[key] ||
        $13 != git_calls[key] || $14 != unlocked[key] || $15 != expected_semantic) {
      print "sample summary mismatch for " $1 ":" $2 > "/dev/stderr"
      exit 1
    }
    compared += 1
  }
  END { if (compared != 42) exit 1 }
' "$comparison_summary" "$comparison_dispersion" || {
  print -u2 -r -- 'raw samples do not reproduce the benchmark summary'
  return 1
}

local accepted_run=$test_tmp/accepted-run
"$root/research/run-core-theme-benchmark.zsh" \
  --output "$accepted_run" \
  --allow-dirty \
  --calibration-iterations 1 \
  --p90-observer-error-ms 2 \
  --max-observer-error-ms 5 \
  -- --target wakamex --iterations 1 --fixture-files 20 --settle-ms 20 \
  >/dev/null
local accepted_metadata
accepted_metadata=$(< "$accepted_run/metadata.txt")
local accepted_median_cpu_psi_percent
accepted_median_cpu_psi_percent=$(print -r -- "$accepted_metadata" | command awk -F= \
  '$1 == "median_sample_cpu_psi_overlap_percent" { print $2; exit }')
[[ -f $accepted_run/summary.tsv \
  && -f $accepted_run/samples.tsv \
  && -f $accepted_run/telemetry.tsv \
  && -f $accepted_run/metadata.txt \
  && $accepted_metadata == *$'accepted=1\n'* \
  && $accepted_metadata == *$'format_version=6\n'* \
  && $accepted_metadata == *$'median_sample_cpu_psi_limit_percent=5.000\n'* \
  && $accepted_median_cpu_psi_percent == <->.<-> \
  && $accepted_metadata == *'sample_rows=3'* \
  && $accepted_metadata == *'telemetry_rows=2'* \
  && $accepted_metadata == *'untimed_semantic_checks=2'* ]] || {
  print -u2 -r -- 'accepted-run bundle is incomplete'
  return 1
}
(( accepted_median_cpu_psi_percent <= 5.0 )) || {
  print -u2 -r -- 'accepted run exceeded the median sample CPU PSI limit'
  return 1
}

local rejected_run=$test_tmp/rejected-run
if "$root/research/run-core-theme-benchmark.zsh" \
    --output "$rejected_run" \
    --allow-dirty \
    --calibration-iterations 1 \
    --p90-observer-error-ms 2 \
    --max-observer-error-ms 5 \
    -- --target does-not-exist --iterations 1 --fixture-files 20 --settle-ms 20 \
    >/dev/null 2>&1; then
  print -u2 -r -- 'invalid accepted run unexpectedly succeeded'
  return 1
fi
[[ ! -e $rejected_run ]] || {
  print -u2 -r -- 'rejected run left a published directory'
  return 1
}

"$root/tests/pty.zsh"

print -r -- 'PASS: end-to-end benchmark and CLI validation'
