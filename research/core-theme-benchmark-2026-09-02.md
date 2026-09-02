# Core theme benchmark - 2026-09-02

How much prompt latency and Git process work do the selected core targets add, and do they render clean, dirty, untracked, staged, and detached-HEAD repository scenarios correctly?

The accepted 20-iteration run found wakamex had the lowest worst retained settled latency among fully correct themes at 8.126 ms. mortalscumbag had the highest first-prompt maximum at 118.289 ms, while Soliah (E) and steeef (E) were the only targets below A correctness.

Each target ran in a fresh interactive PTY against the same 1,000-file Git fixture. The shell was reused for 20 timed transitions in each of clean, tracked-dirty, and untracked state, followed by one untimed staged and detached-HEAD check.

The accepted run started at `2026-09-02T01:43:24Z` from benchmark commit `2a8202573382705a9d423e5818e57d59e774bf3e`, runner SHA-256 `5a02941e176b9f49a05c37d8417a76b96b4a65bcf8812221a82d30ffd3ad5061`, Wakamex commit `0fa4a72ff93c544567760958845ab199808f3017`, OMZ commit `2264a8042763edf2620cfe32d96b096e1f3d26aa`, Pure commit `dbefd0dcafaa3ac7d7222ca50890d9d0c97f7ca2`, Powerlevel10k commit `35833ea15f14b71dbcebc7e54c104d8d56ca5268`, and gitstatusd SHA-256 `02b7bc11a70a68e484c44e3c7e4da1ed403c7b74a94a2b1e169266ea10460c79`.

Artifacts: [`summary.tsv`](core-theme-run-20260902T014321Z/summary.tsv), [`samples.tsv`](core-theme-run-20260902T014321Z/samples.tsv), [`telemetry.tsv`](core-theme-run-20260902T014321Z/telemetry.tsv), [`metadata.txt`](core-theme-run-20260902T014321Z/metadata.txt), and [`dispersion.tsv`](core-theme-run-20260902T014321Z-dispersion.tsv).

## Measurements

State-median ranges cover clean, dirty, and untracked states. Semantic-pass denominators are 20/20/20/1/1 for clean, dirty, untracked, staged, and detached HEAD.

| Theme | First prompt state medians, ms | Settled prompt state medians, ms | Repaints C/D/U | Git calls C/D/U | Unsuppressed calls C/D/U | Semantic passes C/D/U/S/H |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| raw | 0.5-0.6 | 0.5-0.6 | 0/0/0 | 0/0/0 | 0/0/0 | N/A |
| wakamex | 1.5-1.5 | 1.5-7.1 | 0/1/1 | 1/1/1 | 0/0/0 | 20/20/20/1/1 |
| robbyrussell | 6.3-6.9 | 28.5-29.8 | 1/1/1 | 5/5/5 | 0/0/0 | 20/20/20/1/1 |
| agnoster | 81.9-83.1 | 81.9-83.1 | 0/0/0 | 16/16/16 | 14/14/14 | 20/20/20/1/1 |
| bureau | 34.7-34.9 | 34.7-34.9 | 0/0/0 | 5/5/5 | 5/5/5 | 20/20/20/1/1 |
| Soliah | 28.5-29.3 | 28.5-29.3 | 0/0/0 | 4/4/4 | 4/4/4 | 0/0/0/0/1 |
| steeef | 10.9-12.0 | 10.9-12.0 | 0/0/0 | 0/0/0 | 0/0/0 | 20/0/0/1/1 |
| apple | 37.6-39.4 | 37.6-39.4 | 0/0/0 | 7/7/7 | 7/7/7 | 20/20/20/1/1 |
| mortalscumbag | 63.2-65.8 | 63.2-65.8 | 0/0/0 | 7/7/7 | 4/4/4 | 20/20/20/1/1 |
| ys | 16.0-16.7 | 37.4-40.1 | 1/1/1 | 5/5/5 | 0/0/0 | 20/20/20/1/1 |
| bira | 16.9-18.0 | 40.9-42.2 | 1/1/1 | 5/5/5 | 0/0/0 | 20/20/20/1/1 |
| pure | 11.1-12.5 | 24.6-28.3 | 1/1/1 | 6/6/6 | 5/5/5 | 20/20/20/1/1 |
| powerlevel10k-pure | 11.8-13.4 | 12.4-14.5 | 1/1/1 | 0/0/0 | 0/0/0 | 20/20/20/1/1 |
| powerlevel10k-fallback | 12.2-14.2 | 12.2-14.2 | 0/0/0 | 0/0/0 | 0/0/0 | 20/20/20/1/1 |

## Rating rubric

Correctness is a reviewed grade based on the frequency, consequence, and persistence of an observed defect. Only F is an automatic disqualifier, and targets without applicable semantic assertions remain unrated rather than receiving an inferred grade.

| Correctness | Meaning |
| --- | --- |
| A | All tested common and advertised behavior is correct. |
| B | A minor visual or transient defect leaves the final repository state correct. |
| C | An uncommon configuration produces an incorrect result. |
| D | A common workflow has a bounded error in one advertised feature. |
| E | A common workflow leaves core state persistently wrong or stale. |
| F | The theme hangs, corrupts terminal state, expands unsafe input, persistently leaks resources, or makes the shell unusable. |
| Unrated | Semantic coverage is not implemented. |

A feature that the theme does not claim to provide affects scope rather than correctness.

First-prompt and updated-Git latency grades use the worst retained sample for each target minus the raw control maximum of 0.842 ms. A is at most 5 ms, B is at most 15 ms, C is at most 25 ms, D is at most 50 ms, and E is over 50 ms.

Process efficiency uses the largest state-median Git process count: A is at most one, B is two to five, C is six to eight, D is nine to twelve, and E is thirteen or more. Lock hygiene uses the largest state-median share of Git calls without `GIT_OPTIONAL_LOCKS=0`: A is zero, B is at most 25 percent, C is at most 50 percent, D is at most 75 percent, and E is over 75 percent.

Scope explains work but does not reduce user-visible latency. Missed infrastructure names relevant async, registration, or optional-lock improvements absent from the measured path. The consequences remain in the correctness, latency, process, and lock grades rather than being counted twice.

## Rating summary

| Theme | Correctness | First prompt latency | Updated Git latency | Process efficiency | Lock hygiene | Scope | Missed infrastructure |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| raw | Control | A | N/A | N/A | N/A | None | N/A |
| wakamex | A | A | B | A | A | Broad | None |
| robbyrussell | A | B | D | B | A | Standard | None |
| agnoster | A | E | E | E | E | Broad | Async; locks on 14/16 calls |
| bureau | A | D | D | B | E | Broad | Async; locks on 5/5 calls |
| Soliah | E | D | D | B | E | Standard plus commit age | Async registration; locks on 4/4 calls |
| steeef | E | B | Fail | NR | NR | Broad when refreshed | Async; optional locks |
| apple | A | D | D | C | E | Standard | Async; locks on 7/7 calls |
| mortalscumbag | A | E | E | C | D | Broad | Async; locks on 4/7 calls |
| ys | A | C | D | B | A | Standard | None |
| bira | A | C | E | B | A | Standard | None |
| pure | A | C | D | C | E | Broad | Locks on 5/6 calls |
| powerlevel10k-pure | A | C | C | A | A | Broad | None |
| powerlevel10k-fallback | A | C | C | A | A | Broad | None |

## Theme findings

### raw

The unthemed control measures command and PTY overhead without Git or prompt work.

No cutoff or missing feature applies because this target is only the measurement control.

- Correctness: Control - semantic assertions are not applicable. No theme semantics apply.
- First prompt latency: A - state medians were 0.5-0.6 ms and the maximum retained sample was 0.842 ms, or 0.000 ms over the raw maximum.
- Updated Git latency: N/A - The control has no Git state.
- Process efficiency: N/A - The control runs no Git processes.
- Lock hygiene: N/A - The control makes no Git calls.
- Scope: None - Intentionally unthemed.
- Missed infrastructure: N/A - This is the raw Zsh control.

### wakamex

One background status scan returns an editable prompt near the raw floor and repaints when dirty or untracked state arrives.

It omits stash count and commit age, features that add work in bureau and Soliah respectively.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch, detached HEAD, staged, unstaged, and untracked behavior passed every applicable check.
- First prompt latency: A - state medians were 1.5-1.5 ms and the maximum retained sample was 2.014 ms, or 1.172 ms over the raw maximum.
- Updated Git latency: B - settled state medians were 1.5-7.1 ms and the maximum retained sample was 8.126 ms, or 7.284 ms over the raw maximum.
- Process efficiency: A - state medians were 1/1/1 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: A - state medians were 0/0/0 unsuppressed calls out of 1/1/1 total calls.
- Scope: Broad - Branch, detached tag or SHA, staged, unstaged, untracked, topology, and repository actions.
- Missed infrastructure: None - The current custom worker supplies asynchronous execution and optional-lock suppression.

### robbyrussell

OMZ's shared asynchronous helper returns input before five Git processes finish and then repaints with current state.

The theme predates OMZ's async implementation, but current OMZ runs its literal shared git_prompt_info call asynchronously without a theme update.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch plus clean or generic dirty state passed every applicable check, including staged and detached HEAD.
- First prompt latency: B - state medians were 6.3-6.9 ms and the maximum retained sample was 7.723 ms, or 6.881 ms over the raw maximum.
- Updated Git latency: D - settled state medians were 28.5-29.8 ms and the maximum retained sample was 31.618 ms, or 30.776 ms over the raw maximum.
- Process efficiency: B - state medians were 5/5/5 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: A - state medians were 0/0/0 unsuppressed calls out of 5/5/5 total calls.
- Scope: Standard - Branch plus generic clean or dirty state.
- Missed infrastructure: None - Its literal shared-helper call uses current OMZ behavior.

### agnoster

Broad synchronous Git and VCS reporting runs 16 Git processes before the prompt becomes editable.

The theme was updated after both OMZ improvements, but its 2025 Terraform change did not migrate the direct Git work.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch, detached HEAD, and all tested worktree states rendered correctly.
- First prompt latency: E - state medians were 81.9-83.1 ms and the maximum retained sample was 91.357 ms, or 90.515 ms over the raw maximum.
- Updated Git latency: E - settled state medians were 81.9-83.1 ms and the maximum retained sample was 91.357 ms, or 90.515 ms over the raw maximum.
- Process efficiency: E - state medians were 16/16/16 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: E - state medians were 14/14/14 unsuppressed calls out of 16/16/16 total calls.
- Scope: Broad - Branch, detached state, worktree state, topology, repository actions, and several non-Git segments.
- Missed infrastructure: Async; locks on 14/16 calls - The measured path lacks asynchronous execution and optional-lock suppression on 14 of 16 calls.

### bureau

A broad custom collector puts five unsuppressed Git processes on the prompt's critical path.

The theme's 2023 stash update could have used OMZ's lock wrapper, while practical shared async support arrived in 2024.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch, detached HEAD, staged, tracked-dirty, and untracked state rendered correctly.
- First prompt latency: D - state medians were 34.7-34.9 ms and the maximum retained sample was 39.692 ms, or 38.850 ms over the raw maximum.
- Updated Git latency: D - settled state medians were 34.7-34.9 ms and the maximum retained sample was 39.692 ms, or 38.850 ms over the raw maximum.
- Process efficiency: B - state medians were 5/5/5 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: E - state medians were 5/5/5 unsuppressed calls out of 5/5/5 total calls.
- Scope: Broad - Branch, detached SHA, staged, unstaged, untracked, unmerged, topology, and stash state.
- Missed infrastructure: Async; locks on 5/5 calls - The measured path lacks asynchronous execution and optional-lock suppression on all five calls.

### Soliah

Four synchronous calls delay the prompt, and a nested helper mislabels an ordinary branch as detached.

The theme was last touched during OMZ's 2024 async rollout, but current OMZ cannot register the shared helper while it is hidden inside this wrapper.

- Correctness: E - clean 0/20, dirty 0/20, untracked 0/20, staged 0/1, and detached HEAD 1/1. The detached-HEAD scenario passes, but ordinary clean, dirty, untracked, and staged workflows persistently show the wrong branch state.
- First prompt latency: D - state medians were 28.5-29.3 ms and the maximum retained sample was 31.541 ms, or 30.699 ms over the raw maximum.
- Updated Git latency: D - settled state medians were 28.5-29.3 ms and the maximum retained sample was 31.541 ms, or 30.699 ms over the raw maximum.
- Process efficiency: B - state medians were 4/4/4 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: E - state medians were 4/4/4 unsuppressed calls out of 4/4/4 total calls.
- Scope: Standard plus commit age - Branch, generic dirty state, detached label, and last-commit age.
- Missed infrastructure: Async registration; locks on 4/4 calls - The nested helper needs async registration, and all four measured calls lack optional-lock suppression.

### steeef

Its cache avoids prompt-time Git work because ordinary file-changing commands fail to invalidate it.

The theme has not changed since 2018, and current OMZ cannot repair its custom invalidation rule through a shared-helper update.

- Correctness: E - clean 20/20, dirty 0/20, untracked 0/20, staged 1/1, and detached HEAD 1/1. Clean, staged, and detached-HEAD checks pass, but ordinary dirty and untracked commands leave the cached prompt persistently stale.
- First prompt latency: B - state medians were 10.9-12.0 ms and the maximum retained sample was 13.870 ms, or 13.028 ms over the raw maximum.
- Updated Git latency: Fail - No scan ran to observe the measured dirty and untracked transitions.
- Process efficiency: NR - Zero measured calls reflect stale-cache behavior rather than efficient refresh.
- Lock hygiene: NR - Initial collection made nine unsuppressed calls, while the stale measured path made none.
- Scope: Broad when refreshed - Branch, staged, unstaged, untracked, and repository action state when the cache refreshes.
- Missed infrastructure: Async; optional locks - The cache refresh path lacks asynchronous execution and optional-lock suppression.

### apple

Synchronous vcs_info hides seven Git calls behind a theme with no direct Git invocation sites.

Its 2023 icon update could have added lock suppression and untracked detection, while OMZ's shared async helpers do not apply to its separate vcs_info path.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch, detached HEAD, staged, and tracked-dirty behavior passed; untracked state correctly remains clean because the theme does not advertise untracked detection.
- First prompt latency: D - state medians were 37.6-39.4 ms and the maximum retained sample was 49.635 ms, or 48.793 ms over the raw maximum.
- Updated Git latency: D - settled state medians were 37.6-39.4 ms and the maximum retained sample was 49.635 ms, or 48.793 ms over the raw maximum.
- Process efficiency: C - state medians were 7/7/7 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: E - state medians were 7/7/7 unsuppressed calls out of 7/7/7 total calls.
- Scope: Standard - Branch, staged, unstaged, and repository action state across Git, CVS, and SVN.
- Missed infrastructure: Async; locks on 7/7 calls - The measured path lacks asynchronous execution and optional-lock suppression on all seven calls.

### mortalscumbag

A status scan and two materialized log ranges put seven Git processes on every prompt's critical path.

The theme's 2026 escaping fix followed both OMZ improvements, but direct scans and the origin/branch assumption remain.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch, detached HEAD, staged, tracked-dirty, and untracked state rendered correctly.
- First prompt latency: E - state medians were 63.2-65.8 ms and the maximum retained sample was 118.289 ms, or 117.447 ms over the raw maximum.
- Updated Git latency: E - settled state medians were 63.2-65.8 ms and the maximum retained sample was 118.289 ms, or 117.447 ms over the raw maximum.
- Process efficiency: C - state medians were 7/7/7 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: D - state medians were 4/4/4 unsuppressed calls out of 7/7/7 total calls.
- Scope: Broad - Branch, staged, unstaged, untracked, unmerged, and ahead or behind state.
- Missed infrastructure: Async; locks on 4/7 calls - The measured path lacks asynchronous execution and optional-lock suppression on four of seven calls.

### ys

OMZ's shared asynchronous helper returns the editable multi-line prompt before five Git processes finish, then repaints with current state.

The theme has no direct Git calls; its literal shared helper inherits current OMZ asynchronous execution and optional-lock suppression.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch plus clean or generic dirty state passed every applicable check, including staged and detached HEAD.
- First prompt latency: C - state medians were 16.0-16.7 ms and the maximum retained sample was 24.211 ms, or 23.369 ms over the raw maximum.
- Updated Git latency: D - settled state medians were 37.4-40.1 ms and the maximum retained sample was 44.009 ms, or 43.167 ms over the raw maximum.
- Process efficiency: B - state medians were 5/5/5 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: A - state medians were 0/0/0 unsuppressed calls out of 5/5/5 total calls.
- Scope: Standard - Branch plus generic clean or dirty state, with separate SVN and Mercurial prompt support.
- Missed infrastructure: None - Its literal shared-helper call uses current OMZ behavior.

### bira

OMZ's shared asynchronous helper returns the editable multi-line prompt before five Git processes finish, then repaints with current state.

Optional environment segments do not add Git work in this fixture, and its literal shared Git helper inherits current OMZ behavior.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch plus clean or generic dirty state passed every applicable check, including staged and detached HEAD.
- First prompt latency: C - state medians were 16.9-18.0 ms and the maximum retained sample was 20.931 ms, or 20.089 ms over the raw maximum.
- Updated Git latency: E - settled state medians were 40.9-42.2 ms and the maximum retained sample was 55.550 ms, or 54.708 ms over the raw maximum.
- Process efficiency: B - state medians were 5/5/5 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: A - state medians were 0/0/0 unsuppressed calls out of 5/5/5 total calls.
- Scope: Standard - Branch plus generic clean or dirty state, with Mercurial and optional environment segments.
- Missed infrastructure: None - Its literal shared-helper call uses current OMZ behavior.

### pure

Pure returns input near 11 ms and repaints around 24 ms after six Git processes complete.

Background fetch was disabled for the offline comparison; the released status, VCS, topology, and stash tasks remained active.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch, detached HEAD, and clean, staged, unstaged, and untracked state passed every applicable check.
- First prompt latency: C - state medians were 11.1-12.5 ms and the maximum retained sample was 20.883 ms, or 20.041 ms over the raw maximum.
- Updated Git latency: D - settled state medians were 24.6-28.3 ms and the maximum retained sample was 40.884 ms, or 40.042 ms over the raw maximum.
- Process efficiency: C - state medians were 6/6/6 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: E - state medians were 5/5/5 unsuppressed calls out of 6/6/6 total calls.
- Scope: Broad - Branch, detached state, generic worktree state, topology, repository actions, and stash state.
- Missed infrastructure: Locks on 5/6 calls - Five of the six measured Git calls lack optional-lock suppression; the working-tree status scan suppresses locks.

### powerlevel10k-pure

The Pure-style preset returns input around 12 ms and settles after one small gitstatusd repaint without spawning measured Git processes.

The preset deliberately hides tags, remote branches, stashes, and distinct worktree-state indicators while retaining asynchronous status and topology.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch, detached HEAD, and clean or generic dirty state passed every applicable check.
- First prompt latency: C - state medians were 11.8-13.4 ms and the maximum retained sample was 16.029 ms, or 15.187 ms over the raw maximum.
- Updated Git latency: C - settled state medians were 12.4-14.5 ms and the maximum retained sample was 22.790 ms, or 21.948 ms over the raw maximum.
- Process efficiency: A - state medians were 0/0/0 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: A - state medians were 0/0/0 unsuppressed calls out of 0/0/0 total calls.
- Scope: Broad - Branch or detached SHA, generic worktree state, topology, and repository actions.
- Missed infrastructure: None - The measured path already uses gitstatusd asynchronously without prompt-time Git child processes.

### powerlevel10k-fallback

The built-in fallback returns the complete prompt in one render around 12 ms without spawning measured Git processes.

The fallback allows up to 10 ms for synchronous VCS status; this fixture completed on that path without an asynchronous repaint. It is not a wizard-generated preset.

- Correctness: A - clean 20/20, dirty 20/20, untracked 20/20, staged 1/1, and detached HEAD 1/1. Branch, detached HEAD, and distinct clean, staged, unstaged, and untracked state passed every applicable check.
- First prompt latency: C - state medians were 12.2-14.2 ms and the maximum retained sample was 22.618 ms, or 21.776 ms over the raw maximum.
- Updated Git latency: C - settled state medians were 12.2-14.2 ms and the maximum retained sample was 22.618 ms, or 21.776 ms over the raw maximum.
- Process efficiency: A - state medians were 0/0/0 Git calls per transition for clean, dirty, and untracked state.
- Lock hygiene: A - state medians were 0/0/0 unsuppressed calls out of 0/0/0 total calls.
- Scope: Broad - Branch or detached SHA, distinct worktree state, topology, repository actions, tags, remote branches, and stash state.
- Missed infrastructure: None - The measured path uses gitstatusd and exposes the built-in status features without prompt-time Git child processes.

## Measurement quality and generation

The runner waits on the PTY master descriptor and timestamps each read as it arrives. TSV latency has 0.001 ms numeric precision, while calibration measured scheduler-dependent reader lateness separately: pre-run p90 0.162 ms and maximum 0.196 ms, then post-run p90 0.174 ms and maximum 0.189 ms. The run stayed below the 0.500 ms p90 and 5.000 ms maximum acceptance limits.

Median per-sample CPU PSI overlap was 0.674 percent, below the current 5 percent rejection threshold. The generator independently recomputed this value from the retained sample counters.

This report was generated by [`generate-core-theme-report.zsh`](generate-core-theme-report.zsh). Numeric evidence and mechanistic grades come from the accepted summary and reproduced dispersion. Correctness grades come from [`core-theme-correctness-assessment.tsv`](core-theme-correctness-assessment.tsv), and generation stops if any of its five reviewed semantic outcomes changed. Narrative judgments and explicit grade exceptions come from [`core-theme-report-annotations.tsv`](core-theme-report-annotations.tsv).
