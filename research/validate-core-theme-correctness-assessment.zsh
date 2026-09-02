#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail

usage() {
  print -r -- 'usage: validate-core-theme-correctness-assessment.zsh SUMMARY.tsv [ASSESSMENT.tsv]'
  print -r --
  print -r -- 'Reject manual correctness grades whose reviewed semantic outcomes differ from a benchmark summary.'
}

if (( $# == 1 )) && [[ $1 == -h || $1 == --help ]]; then
  usage
  return 0
fi
(( $# == 1 || $# == 2 )) || {
  usage >&2
  return 1
}

local script_dir=${0:A:h}
local summary=${1:A}
local assessment_input=${2:-$script_dir/core-theme-correctness-assessment.tsv}
local assessment=${assessment_input:A}

[[ -r $summary ]] || {
  print -u2 -r -- "error: summary is not readable: $summary"
  return 1
}
[[ -r $assessment ]] || {
  print -u2 -r -- "error: assessment is not readable: $assessment"
  return 1
}

command awk -F '\t' -v assessment="$assessment" '
  function fail(message) {
    print "error: " message > "/dev/stderr"
    failed = 1
  }

  function classify_timed(value, iterations) {
    if (value == "na") return "na"
    if (value !~ /^[0-9]+$/ || value > iterations) return "invalid"
    if (value == iterations) return "pass"
    if (value == 0) return "fail"
    return "partial"
  }

  function classify_untimed(value) {
    if (value == "na") return "na"
    if (value == 1) return "pass"
    if (value == 0) return "fail"
    return "invalid"
  }

  BEGIN {
    expected_assessment_header = "target\tcorrectness_grade\tclean_semantic\tdirty_semantic\tuntracked_semantic\tstaged_semantic\tdetached_head_semantic"
    while ((getline line < assessment) > 0) {
      if (++assessment_row == 1) {
        if (line != expected_assessment_header) fail("assessment TSV has an unexpected header")
        continue
      }
      fields = split(line, item, "\t")
      if (fields != 7 || item[1] == "" || (item[1] in grade)) {
        fail("invalid or duplicate assessment target at row " assessment_row)
        continue
      }
      if (item[2] !~ /^(Control|[A-F]|Unrated)$/) fail("invalid correctness grade for " item[1] ": " item[2])
      for (i = 3; i <= 7; i++) {
        if (item[i] !~ /^(pass|fail|na)$/) fail("invalid reviewed semantic outcome for " item[1] ": " item[i])
      }
      grade[item[1]] = item[2]
      expected[item[1], "clean"] = item[3]
      expected[item[1], "dirty"] = item[4]
      expected[item[1], "untracked"] = item[5]
      expected[item[1], "staged"] = item[6]
      expected[item[1], "detached-head"] = item[7]
      assessment_targets++
    }
    close(assessment)
    if (assessment_row < 2) fail("assessment TSV has no target rows")
    assessment_valid = !failed
  }

  NR == 1 {
    header_valid = 1
    for (i = 1; i <= NF; i++) column[$i] = i
    required[1] = "target"
    required[2] = "iterations"
    required[3] = "clean_semantic_passes"
    required[4] = "dirty_semantic_passes"
    required[5] = "untracked_semantic_passes"
    required[6] = "staged_semantic_pass"
    required[7] = "detached_head_semantic_pass"
    for (i = 1; i <= 7; i++) {
      if (!(required[i] in column)) {
        fail("summary TSV lacks " required[i])
        header_valid = 0
      }
    }
    next
  }

  !assessment_valid || !header_valid { next }

  {
    target = $(column["target"])
    iterations = $(column["iterations"])
    if (target == "" || seen[target]++) {
      fail("invalid or duplicate summary target at row " NR)
      next
    }
    if (!(target in grade)) {
      fail("summary target has no reviewed correctness assessment: " target)
      next
    }
    if (iterations !~ /^[1-9][0-9]*$/) {
      fail("invalid iteration count for " target ": " iterations)
      next
    }

    actual[target, "clean"] = classify_timed($(column["clean_semantic_passes"]), iterations)
    actual[target, "dirty"] = classify_timed($(column["dirty_semantic_passes"]), iterations)
    actual[target, "untracked"] = classify_timed($(column["untracked_semantic_passes"]), iterations)
    actual[target, "staged"] = classify_untimed($(column["staged_semantic_pass"]))
    actual[target, "detached-head"] = classify_untimed($(column["detached_head_semantic_pass"]))
    scenarios[1] = "clean"
    scenarios[2] = "dirty"
    scenarios[3] = "untracked"
    scenarios[4] = "staged"
    scenarios[5] = "detached-head"
    for (i = 1; i <= 5; i++) {
      scenario = scenarios[i]
      if (actual[target, scenario] == "invalid") {
        fail("invalid " scenario " semantic result for " target)
      } else if (actual[target, scenario] == "partial") {
        fail("correctness grade " grade[target] " for " target " is stale: " scenario " semantics are mixed and require review")
      } else if (actual[target, scenario] != expected[target, scenario]) {
        fail("correctness grade " grade[target] " for " target " is stale: " scenario " semantics changed from " expected[target, scenario] " to " actual[target, scenario])
      }
    }
    summary_targets++
  }

  END {
    if (!assessment_valid || !header_valid) exit 1
    for (target in grade) {
      if (!(target in seen)) fail("reviewed correctness assessment has no summary target: " target)
    }
    if (summary_targets != assessment_targets) fail("summary and assessment target counts differ")
    if (failed) exit 1
    print "correctness assessments current for " summary_targets " targets"
  }
' "$summary"
