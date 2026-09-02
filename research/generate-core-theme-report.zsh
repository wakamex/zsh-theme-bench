#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail

usage() {
  print -r -- 'usage: generate-core-theme-report.zsh RUN-DIRECTORY OUTPUT.md'
  print -r --
  print -r -- 'Generate an atomic hybrid report from one accepted core-theme run.'
}

fail() {
  print -u2 -r -- "error: $*"
  return 1
}

if (( $# == 1 )) && [[ $1 == -h || $1 == --help ]]; then
  usage
  return 0
fi
(( $# == 2 )) || {
  usage >&2
  return 1
}

local script_dir=${0:A:h}
local run=${1:A}
local output=${2:A}
local summary=$run/summary.tsv
local samples=$run/samples.tsv
local telemetry=$run/telemetry.tsv
local metadata=$run/metadata.txt
local dispersion=${run}-dispersion.tsv
local assessment=$script_dir/core-theme-correctness-assessment.tsv
local annotations=$script_dir/core-theme-report-annotations.tsv
local validator=$script_dir/validate-core-theme-correctness-assessment.zsh
local summarizer=$script_dir/summarize-core-theme-samples.zsh
local output_dir=${output:h}

[[ -d $run ]] || fail "run directory does not exist: $run"
for required_file in $summary $samples $telemetry $metadata $dispersion $assessment $annotations $validator $summarizer; do
  [[ -r $required_file ]] || fail "required input is not readable: $required_file"
done
[[ -d $output_dir ]] || fail "output directory does not exist: $output_dir"
for required_command in awk gawk sha256sum cmp mktemp realpath; do
  (( $+commands[$required_command] )) || fail "$required_command is required"
done

metadata_value() {
  local key=$1
  command awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; found = 1; exit } END { if (!found) exit 1 }' "$metadata"
}

local accepted
accepted=$(metadata_value accepted) || fail 'metadata lacks accepted'
[[ $accepted == 1 ]] || fail 'run metadata is not accepted'

local artifact expected_hash actual_hash
for artifact in summary samples telemetry; do
  expected_hash=$(metadata_value "${artifact}_sha256") || fail "metadata lacks ${artifact}_sha256"
  actual_hash=$(command sha256sum "$run/${artifact}.tsv" | command awk '{print $1}')
  [[ $actual_hash == $expected_hash ]] || fail "$artifact hash differs from accepted metadata"
done

"$validator" "$summary" "$assessment" || fail 'correctness assessment is stale'

local dispersion_tmp report_tmp
dispersion_tmp=$(command mktemp "$output_dir/.core-theme-dispersion.XXXXXX") || fail 'could not create temporary dispersion file'
report_tmp=$(command mktemp "$output_dir/.${output:t}.XXXXXX") || {
  command rm -f -- "$dispersion_tmp"
  fail 'could not create temporary report file'
}
trap 'command rm -f -- "$dispersion_tmp" "$report_tmp"' EXIT INT TERM HUP

"$summarizer" "$samples" > "$dispersion_tmp" || fail 'could not reproduce dispersion from samples'
command cmp -s "$dispersion_tmp" "$dispersion" || fail 'stored dispersion does not match samples'

local cpu_psi_median
cpu_psi_median=$(command gawk -F '\t' '
  NR == 1 { next }
  {
    duration_us = ($21 - $20) * 1000000
    if (duration_us <= 0) exit 1
    overlap[++count] = 100 * ($23 - $22) / duration_us
  }
  END {
    if (!count) exit 1
    asort(overlap)
    middle = int(count / 2)
    median = count % 2 ? overlap[middle + 1] : (overlap[middle] + overlap[middle + 1]) / 2
    printf "%.3f", median
  }
' "$samples") || fail 'could not calculate median per-sample CPU PSI overlap'

local run_link dispersion_link assessment_link annotations_link generator_link
run_link=$(command realpath --relative-to="$output_dir" "$run")
dispersion_link=$(command realpath --relative-to="$output_dir" "$dispersion")
assessment_link=$(command realpath --relative-to="$output_dir" "$assessment")
annotations_link=$(command realpath --relative-to="$output_dir" "$annotations")
generator_link=$(command realpath --relative-to="$output_dir" "$0")

command gawk -F '\t' \
  -v metadata="$metadata" \
  -v dispersion="$dispersion" \
  -v assessment="$assessment" \
  -v annotations="$annotations" \
  -v run_link="$run_link" \
  -v dispersion_link="$dispersion_link" \
  -v assessment_link="$assessment_link" \
  -v annotations_link="$annotations_link" \
  -v generator_link="$generator_link" \
  -v cpu_psi_median="$cpu_psi_median" '
  function die(message) {
    print "error: " message > "/dev/stderr"
    exit 1
  }

  function read_key_values(file, destination, line, separator, key) {
    while ((getline line < file) > 0) {
      separator = index(line, "=")
      if (!separator) die("invalid metadata line: " line)
      key = substr(line, 1, separator - 1)
      destination[key] = substr(line, separator + 1)
    }
    close(file)
  }

  function read_assessments(file, line, field, count, target) {
    while ((getline line < file) > 0) {
      count++
      split(line, field, "\t")
      if (count == 1) {
        if (line != "target\tcorrectness_grade\tclean_semantic\tdirty_semantic\tuntracked_semantic\tstaged_semantic\tdetached_head_semantic") die("unexpected assessment header")
        continue
      }
      target = field[1]
      correctness_grade[target] = field[2]
      assessed[target] = 1
      assessment_count++
    }
    close(file)
  }

  function read_annotations(file, line, field, count, target, i) {
    while ((getline line < file) > 0) {
      count++
      if (count == 1) {
        if (line != "target\tfinding\tcontext\tcorrectness_rationale\tscope_label\tscope_detail\tmissed_label\tmissed_detail\tupdated_grade_override\tupdated_explanation\tprocess_grade_override\tprocess_explanation\tlock_grade_override\tlock_explanation") die("unexpected report annotation header")
        continue
      }
      if (split(line, field, "\t") != 14) die("invalid report annotation row " count)
      target = field[1]
      if (target in annotated) die("duplicate report annotation for " target)
      annotated[target] = 1
      for (i = 2; i <= 14; i++) note[target, i] = field[i]
      annotation_count++
    }
    close(file)
  }

  function read_dispersion(file, line, field, header, count, target, state, key, i) {
    while ((getline line < file) > 0) {
      count++
      split(line, field, "\t")
      if (count == 1) {
        for (i = 1; i <= length(field); i++) header[field[i]] = i
        if (!("target" in header) || !("state" in header) || !("first_max_ms" in header) || !("settled_max_ms" in header)) die("dispersion lacks required columns")
        continue
      }
      target = field[header["target"]]
      state = field[header["state"]]
      key = target SUBSEP state
      if (key in dispersion_seen) die("duplicate dispersion row for " target ":" state)
      dispersion_seen[key] = 1
      first_max[target, state] = field[header["first_max_ms"]] + 0
      settled_max[target, state] = field[header["settled_max_ms"]] + 0
      dispersion_count++
    }
    close(file)
  }

  function minimum3(a, b, c) { return a < b ? (a < c ? a : c) : (b < c ? b : c) }
  function maximum3(a, b, c) { return a > b ? (a > c ? a : c) : (b > c ? b : c) }
  function range1(a, b, c) { return sprintf("%.1f-%.1f", minimum3(a, b, c), maximum3(a, b, c)) }
  function triplet0(a, b, c) { return sprintf("%.0f/%.0f/%.0f", a, b, c) }

  function integer_with_commas(value, result, suffix) {
    result = sprintf("%d", value)
    suffix = ""
    while (length(result) > 3) {
      suffix = "," substr(result, length(result) - 2) suffix
      result = substr(result, 1, length(result) - 3)
    }
    return result suffix
  }

  function latency_grade(added) {
    if (added <= 5) return "A"
    if (added <= 15) return "B"
    if (added <= 25) return "C"
    if (added <= 50) return "D"
    return "E"
  }

  function process_grade(calls) {
    if (calls <= 1) return "A"
    if (calls <= 5) return "B"
    if (calls <= 8) return "C"
    if (calls <= 12) return "D"
    return "E"
  }

  function lock_grade(share) {
    if (share == 0) return "A"
    if (share <= 25) return "B"
    if (share <= 50) return "C"
    if (share <= 75) return "D"
    return "E"
  }

  function state_semantics(target) {
    if (clean_sem[target] == "na") return "N/A"
    return clean_sem[target] "/" dirty_sem[target] "/" untracked_sem[target] "/" staged_sem[target] "/" detached_sem[target]
  }

  function detailed_semantics(target) {
    if (clean_sem[target] == "na") return "semantic assertions are not applicable"
    return "clean " clean_sem[target] "/" iterations[target] ", dirty " dirty_sem[target] "/" iterations[target] ", untracked " untracked_sem[target] "/" iterations[target] ", staged " staged_sem[target] "/1, and detached HEAD " detached_sem[target] "/1"
  }

  function join_names(values, count, result, i) {
    result = ""
    for (i = 1; i <= count; i++) {
      if (i > 1) result = result (i == count ? " and " : ", ")
      result = result values[i]
    }
    return result
  }

  BEGIN {
    OFS = "\t"
    read_key_values(metadata, meta)
    read_assessments(assessment)
    read_annotations(annotations)
    read_dispersion(dispersion)
  }

  NR == 1 {
    for (i = 1; i <= NF; i++) column[$i] = i
    required[1] = "snapshot_at_utc"
    required[2] = "benchmark_commit"
    required[3] = "target"
    required[4] = "target_commit"
    required[5] = "omz_commit"
    required[6] = "iterations"
    required[7] = "fixture_files"
    required[8] = "settle_ms"
    required[9] = "clean_first_ms"
    required[10] = "clean_settled_ms"
    required[11] = "clean_repaints"
    required[12] = "clean_git_calls"
    required[13] = "clean_unlocked_calls"
    required[14] = "clean_semantic_passes"
    required[15] = "dirty_first_ms"
    required[16] = "dirty_settled_ms"
    required[17] = "dirty_repaints"
    required[18] = "dirty_git_calls"
    required[19] = "dirty_unlocked_calls"
    required[20] = "dirty_semantic_passes"
    required[21] = "untracked_first_ms"
    required[22] = "untracked_settled_ms"
    required[23] = "untracked_repaints"
    required[24] = "untracked_git_calls"
    required[25] = "untracked_unlocked_calls"
    required[26] = "untracked_semantic_passes"
    required[27] = "staged_semantic_pass"
    required[28] = "detached_head_semantic_pass"
    for (i = 1; i <= 28; i++) if (!(required[i] in column)) die("summary lacks " required[i])
    next
  }

  {
    target = $(column["target"])
    if (target in summary_seen) die("duplicate summary row for " target)
    if (!(target in assessed)) die("missing correctness assessment for " target)
    if (!(target in annotated)) die("missing report annotation for " target)
    summary_seen[target] = 1
    order[++target_count] = target
    snapshot[target] = $(column["snapshot_at_utc"])
    benchmark_commit[target] = $(column["benchmark_commit"])
    target_commit[target] = $(column["target_commit"])
    omz_commit[target] = $(column["omz_commit"])
    iterations[target] = $(column["iterations"])
    fixture_files[target] = $(column["fixture_files"])
    settle_ms[target] = $(column["settle_ms"])
    first_clean[target] = $(column["clean_first_ms"]) + 0
    first_dirty[target] = $(column["dirty_first_ms"]) + 0
    first_untracked[target] = $(column["untracked_first_ms"]) + 0
    settled_clean[target] = $(column["clean_settled_ms"]) + 0
    settled_dirty[target] = $(column["dirty_settled_ms"]) + 0
    settled_untracked[target] = $(column["untracked_settled_ms"]) + 0
    repaint_clean[target] = $(column["clean_repaints"]) + 0
    repaint_dirty[target] = $(column["dirty_repaints"]) + 0
    repaint_untracked[target] = $(column["untracked_repaints"]) + 0
    calls_clean[target] = $(column["clean_git_calls"]) + 0
    calls_dirty[target] = $(column["dirty_git_calls"]) + 0
    calls_untracked[target] = $(column["untracked_git_calls"]) + 0
    unlocked_clean[target] = $(column["clean_unlocked_calls"]) + 0
    unlocked_dirty[target] = $(column["dirty_unlocked_calls"]) + 0
    unlocked_untracked[target] = $(column["untracked_unlocked_calls"]) + 0
    clean_sem[target] = $(column["clean_semantic_passes"])
    dirty_sem[target] = $(column["dirty_semantic_passes"])
    untracked_sem[target] = $(column["untracked_semantic_passes"])
    staged_sem[target] = $(column["staged_semantic_pass"])
    detached_sem[target] = $(column["detached_head_semantic_pass"])
  }

  END {
    if (!target_count) die("summary has no targets")
    if (target_count != assessment_count || target_count != annotation_count) die("summary, assessment, and annotation target counts differ")
    for (i = 1; i <= target_count; i++) {
      target = order[i]
      for (s = 1; s <= 3; s++) {
        state = s == 1 ? "clean" : (s == 2 ? "dirty" : "untracked")
        if (!((target SUBSEP state) in dispersion_seen)) die("missing dispersion row for " target ":" state)
      }
    }

    raw_max = maximum3(first_max["raw", "clean"], first_max["raw", "dirty"], first_max["raw", "untracked"])
    for (i = 1; i <= target_count; i++) {
      target = order[i]
      max_first[target] = maximum3(first_max[target, "clean"], first_max[target, "dirty"], first_max[target, "untracked"])
      max_settled[target] = maximum3(settled_max[target, "clean"], settled_max[target, "dirty"], settled_max[target, "untracked"])
      first_added[target] = max_first[target] - raw_max
      if (first_added[target] < 0) first_added[target] = 0
      settled_added[target] = max_settled[target] - raw_max
      if (settled_added[target] < 0) settled_added[target] = 0
      first_grade[target] = latency_grade(first_added[target])
      updated_grade[target] = note[target, 9] == "auto" ? latency_grade(settled_added[target]) : note[target, 9]
      max_calls[target] = maximum3(calls_clean[target], calls_dirty[target], calls_untracked[target])
      process_result[target] = note[target, 11] == "auto" ? process_grade(max_calls[target]) : note[target, 11]
      max_share[target] = 0
      if (calls_clean[target] > 0) max_share[target] = 100 * unlocked_clean[target] / calls_clean[target]
      if (calls_dirty[target] > 0 && 100 * unlocked_dirty[target] / calls_dirty[target] > max_share[target]) max_share[target] = 100 * unlocked_dirty[target] / calls_dirty[target]
      if (calls_untracked[target] > 0 && 100 * unlocked_untracked[target] / calls_untracked[target] > max_share[target]) max_share[target] = 100 * unlocked_untracked[target] / calls_untracked[target]
      lock_result[target] = note[target, 13] == "auto" ? lock_grade(max_share[target]) : note[target, 13]
      if (target != "raw" && correctness_grade[target] == "A" && (!fastest || max_settled[target] < max_settled[fastest])) fastest = target
      if (target != "raw" && (!slowest || max_first[target] > max_first[slowest])) slowest = target
      if (correctness_grade[target] !~ /^(A|Control)$/) correctness_issue[++correctness_issue_count] = target " (" correctness_grade[target] ")"
    }

    report_date = substr(snapshot[order[1]], 1, 10)
    print "# Core theme benchmark - " report_date
    print ""
    print "How much prompt latency and Git process work do the selected core targets add, and do they render clean, dirty, untracked, staged, and detached-HEAD repository scenarios correctly?"
    print ""
    printf "The accepted %d-iteration run found %s had the lowest worst retained settled latency among fully correct themes at %.3f ms. %s had the highest first-prompt maximum at %.3f ms", iterations[order[1]], fastest, max_settled[fastest], slowest, max_first[slowest]
    if (correctness_issue_count) printf ", while %s were the only targets below A correctness", join_names(correctness_issue, correctness_issue_count)
    print "."
    print ""
    printf "Each target ran in a fresh interactive PTY against the same %s-file Git fixture. The shell was reused for %d timed transitions in each of clean, tracked-dirty, and untracked state, followed by one untimed staged and detached-HEAD check.\n", integer_with_commas(fixture_files[order[1]]), iterations[order[1]]
    print ""
    printf "The accepted run started at `%s` from benchmark commit `%s`, runner SHA-256 `%s`, Wakamex commit `%s`, OMZ commit `%s`, Pure commit `%s`, Powerlevel10k commit `%s`, and gitstatusd SHA-256 `%s`.\n", snapshot[order[1]], meta["benchmark_commit"], meta["runner_sha256"], target_commit["wakamex"], meta["omz_commit"], meta["pure_commit"], meta["powerlevel10k_commit"], meta["powerlevel10k_gitstatusd_sha256"]
    print ""
    printf "Artifacts: [`summary.tsv`](%s/summary.tsv), [`samples.tsv`](%s/samples.tsv), [`telemetry.tsv`](%s/telemetry.tsv), [`metadata.txt`](%s/metadata.txt), and [`dispersion.tsv`](%s).\n", run_link, run_link, run_link, run_link, dispersion_link
    print ""
    print "## Measurements"
    print ""
    printf "State-median ranges cover clean, dirty, and untracked states. Semantic-pass denominators are %d/%d/%d/1/1 for clean, dirty, untracked, staged, and detached HEAD.\n", iterations[order[1]], iterations[order[1]], iterations[order[1]]
    print ""
    print "| Theme | First prompt state medians, ms | Settled prompt state medians, ms | Repaints C/D/U | Git calls C/D/U | Unsuppressed calls C/D/U | Semantic passes C/D/U/S/H |"
    print "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"
    for (i = 1; i <= target_count; i++) {
      target = order[i]
      printf "| %s | %s | %s | %s | %s | %s | %s |\n", target, range1(first_clean[target], first_dirty[target], first_untracked[target]), range1(settled_clean[target], settled_dirty[target], settled_untracked[target]), triplet0(repaint_clean[target], repaint_dirty[target], repaint_untracked[target]), triplet0(calls_clean[target], calls_dirty[target], calls_untracked[target]), triplet0(unlocked_clean[target], unlocked_dirty[target], unlocked_untracked[target]), state_semantics(target)
    }
    print ""
    print "## Rating rubric"
    print ""
    print "Correctness is a reviewed grade based on the frequency, consequence, and persistence of an observed defect. Only F is an automatic disqualifier, and targets without applicable semantic assertions remain unrated rather than receiving an inferred grade."
    print ""
    print "| Correctness | Meaning |"
    print "| --- | --- |"
    print "| A | All tested common and advertised behavior is correct. |"
    print "| B | A minor visual or transient defect leaves the final repository state correct. |"
    print "| C | An uncommon configuration produces an incorrect result. |"
    print "| D | A common workflow has a bounded error in one advertised feature. |"
    print "| E | A common workflow leaves core state persistently wrong or stale. |"
    print "| F | The theme hangs, corrupts terminal state, expands unsafe input, persistently leaks resources, or makes the shell unusable. |"
    print "| Unrated | Semantic coverage is not implemented. |"
    print ""
    print "A feature that the theme does not claim to provide affects scope rather than correctness."
    print ""
    printf "First-prompt and updated-Git latency grades use the worst retained sample for each target minus the raw control maximum of %.3f ms. A is at most 5 ms, B is at most 15 ms, C is at most 25 ms, D is at most 50 ms, and E is over 50 ms.\n", raw_max
    print ""
    print "Process efficiency uses the largest state-median Git process count: A is at most one, B is two to five, C is six to eight, D is nine to twelve, and E is thirteen or more. Lock hygiene uses the largest state-median share of Git calls without `GIT_OPTIONAL_LOCKS=0`: A is zero, B is at most 25 percent, C is at most 50 percent, D is at most 75 percent, and E is over 75 percent."
    print ""
    print "Scope explains work but does not reduce user-visible latency. Missed infrastructure names relevant async, registration, or optional-lock improvements absent from the measured path. The consequences remain in the correctness, latency, process, and lock grades rather than being counted twice."
    print ""
    print "## Rating summary"
    print ""
    print "| Theme | Correctness | First prompt latency | Updated Git latency | Process efficiency | Lock hygiene | Scope | Missed infrastructure |"
    print "| --- | --- | ---: | ---: | ---: | ---: | --- | --- |"
    for (i = 1; i <= target_count; i++) {
      target = order[i]
      printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n", target, correctness_grade[target], first_grade[target], updated_grade[target], process_result[target], lock_result[target], note[target, 5], note[target, 7]
    }
    print ""
    print "## Theme findings"
    for (i = 1; i <= target_count; i++) {
      target = order[i]
      print ""
      print "### " target
      print ""
      print note[target, 2]
      print ""
      print note[target, 3]
      print ""
      printf "- Correctness: %s - %s. %s\n", correctness_grade[target], detailed_semantics(target), note[target, 4]
      printf "- First prompt latency: %s - state medians were %s ms and the maximum retained sample was %.3f ms, or %.3f ms over the raw maximum.\n", first_grade[target], range1(first_clean[target], first_dirty[target], first_untracked[target]), max_first[target], first_added[target]
      if (note[target, 10] == "auto") {
        printf "- Updated Git latency: %s - settled state medians were %s ms and the maximum retained sample was %.3f ms, or %.3f ms over the raw maximum.\n", updated_grade[target], range1(settled_clean[target], settled_dirty[target], settled_untracked[target]), max_settled[target], settled_added[target]
      } else {
        printf "- Updated Git latency: %s - %s\n", updated_grade[target], note[target, 10]
      }
      if (note[target, 12] == "auto") {
        printf "- Process efficiency: %s - state medians were %s Git calls per transition for clean, dirty, and untracked state.\n", process_result[target], triplet0(calls_clean[target], calls_dirty[target], calls_untracked[target])
      } else {
        printf "- Process efficiency: %s - %s\n", process_result[target], note[target, 12]
      }
      if (note[target, 14] == "auto") {
        printf "- Lock hygiene: %s - state medians were %s unsuppressed calls out of %s total calls.\n", lock_result[target], triplet0(unlocked_clean[target], unlocked_dirty[target], unlocked_untracked[target]), triplet0(calls_clean[target], calls_dirty[target], calls_untracked[target])
      } else {
        printf "- Lock hygiene: %s - %s\n", lock_result[target], note[target, 14]
      }
      printf "- Scope: %s - %s\n", note[target, 5], note[target, 6]
      printf "- Missed infrastructure: %s - %s\n", note[target, 7], note[target, 8]
    }
    print ""
    print "## Measurement quality and generation"
    print ""
    printf "The runner waits on the PTY master descriptor and timestamps each read as it arrives. TSV latency has 0.001 ms numeric precision, while calibration measured scheduler-dependent reader lateness separately: pre-run p90 %.3f ms and maximum %.3f ms, then post-run p90 %.3f ms and maximum %.3f ms. The run stayed below the 0.500 ms p90 and 5.000 ms maximum acceptance limits.\n", meta["pre_calibration_p90_observer_error_ms"], meta["pre_calibration_max_observer_error_ms"], meta["post_calibration_p90_observer_error_ms"], meta["post_calibration_max_observer_error_ms"]
    print ""
    printf "Median per-sample CPU PSI overlap was %s percent, below the current 5 percent rejection threshold. The generator independently recomputed this value from the retained sample counters.\n", cpu_psi_median
    print ""
    printf "This report was generated by [`generate-core-theme-report.zsh`](%s). Numeric evidence and mechanistic grades come from the accepted summary and reproduced dispersion. Correctness grades come from [`core-theme-correctness-assessment.tsv`](%s), and generation stops if any of its five reviewed semantic outcomes changed. Narrative judgments and explicit grade exceptions come from [`core-theme-report-annotations.tsv`](%s).\n", generator_link, assessment_link, annotations_link
  }
' "$summary" > "$report_tmp" || fail 'report generation failed'

command mv -f -- "$report_tmp" "$output" || fail 'could not publish report'
report_tmp=
command rm -f -- "$dispersion_tmp"
dispersion_tmp=
trap - EXIT INT TERM HUP

print -r -- "report=$output"
