#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail

usage() {
  print -r -- 'usage: summarize-core-theme-samples.zsh SAMPLES.tsv'
  print -r --
  print -r -- 'Summarize long-form core theme samples as median, p10, p90, and maximum TSV.'
}

if (( $# == 1 )) && [[ $1 == -h || $1 == --help ]]; then
  usage
  return 0
fi
(( $# == 1 )) || {
  usage >&2
  return 1
}

local samples=${1:A}
[[ -r $samples ]] || {
  print -u2 -r -- "error: samples are not readable: $samples"
  return 1
}
(( $+commands[gawk] )) || {
  print -u2 -r -- 'error: gawk is required'
  return 1
}

command gawk -F '\t' '
  function sorted_copy(metric, key, n, destination, i) {
    delete destination
    for (i = 1; i <= n; i++) destination[i] = metric[key, i]
    asort(destination)
  }

  function median(metric, key, n, values, middle) {
    sorted_copy(metric, key, n, values)
    middle = int(n / 2)
    if (n % 2) return values[middle + 1]
    return (values[middle] + values[middle + 1]) / 2
  }

  function percentile(metric, key, n, percentage, values, rank) {
    sorted_copy(metric, key, n, values)
    rank = int((percentage * n + 99) / 100)
    return values[rank]
  }

  BEGIN {
    base_header = "snapshot_at_utc\tbenchmark_commit\trunner_sha256\ttarget\ttarget_kind\ttarget_commit\tomz_commit\tzsh_version\tgit_version\tfixture_files\tsettle_ms\tstate\titeration\tfirst_ms\tsettled_ms\trepaints\tgit_calls\tunlocked_calls\tsemantic_pass"
    pressure_suffix = "\tmeasurement_started_epoch_seconds\tmeasurement_finished_epoch_seconds\tcpu_psi_some_total_before\tcpu_psi_some_total_after"
    OFS = "\t"
  }

  NR == 1 {
    if ($0 == base_header) {
      expected_fields = 19
    } else if ($0 == base_header pressure_suffix) {
      expected_fields = 23
    } else {
      print "error: unexpected sample header" > "/dev/stderr"
      exit 1
    }
    next
  }

  NF != expected_fields {
    print "error: row " NR " has " NF " fields; expected " expected_fields > "/dev/stderr"
    exit 1
  }

  {
    key = $4 SUBSEP $12
    iteration = $13 + 0
    if (iteration < 1 || $13 !~ /^[0-9]+$/ || seen_iteration[key, iteration]++) {
      print "error: invalid or duplicate iteration at row " NR > "/dev/stderr"
      exit 1
    }
    if (!(key in seen_group)) {
      seen_group[key] = 1
      group_order[++group_count] = key
      target[key] = $4
      state[key] = $12
    }
    n = ++count[key]
    if (iteration > max_iteration[key]) max_iteration[key] = iteration
    first_ms[key, n] = $14 + 0
    settled_ms[key, n] = $15 + 0
    repaints[key, n] = $16 + 0
    git_calls[key, n] = $17 + 0
    unlocked_calls[key, n] = $18 + 0
    if ($19 == "na") {
      semantic_na[key] = 1
    } else if ($19 == 0 || $19 == 1) {
      semantic_passes[key] += $19
    } else {
      print "error: invalid semantic result at row " NR > "/dev/stderr"
      exit 1
    }
    if (expected_fields == 23 &&
        ($20 !~ /^[0-9]+[.][0-9]+$/ || $21 !~ /^[0-9]+[.][0-9]+$/ ||
         $22 !~ /^[0-9]+$/ || $23 !~ /^[0-9]+$/ ||
         ($21 + 0) < ($20 + 0) || ($23 + 0) < ($22 + 0))) {
      print "error: invalid per-sample CPU pressure interval at row " NR > "/dev/stderr"
      exit 1
    }
  }

  END {
    if (!group_count) exit 1
    print "target", "state", "samples", "first_median_ms", "first_p10_ms", "first_p90_ms", "first_max_ms", "settled_median_ms", "settled_p10_ms", "settled_p90_ms", "settled_max_ms", "repaints_median", "git_calls_median", "unlocked_calls_median", "semantic_passes"
    for (group_index = 1; group_index <= group_count; group_index++) {
      key = group_order[group_index]
      n = count[key]
      if (max_iteration[key] != n) {
        print "error: non-contiguous iterations for " target[key] ":" state[key] > "/dev/stderr"
        exit 1
      }
      semantic = semantic_na[key] ? "na" : semantic_passes[key] "/" n
      printf "%s\t%s\t%d\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%s\n", \
        target[key], state[key], n, \
        median(first_ms, key, n), \
        percentile(first_ms, key, n, 10), \
        percentile(first_ms, key, n, 90), \
        percentile(first_ms, key, n, 100), \
        median(settled_ms, key, n), \
        percentile(settled_ms, key, n, 10), \
        percentile(settled_ms, key, n, 90), \
        percentile(settled_ms, key, n, 100), \
        median(repaints, key, n), \
        median(git_calls, key, n), \
        median(unlocked_calls, key, n), semantic
    }
  }
' "$samples"
