# Methodology

`zsh-theme-bench` measures prompt behavior through the same interactive paths a user exercises. It separates the time until input is accepted from the time until Git information is current, checks rendered repository state, counts Git processes, records optional-lock handling, and retains the evidence needed to reproduce an accepted comparison.

## Two benchmark layers

The focused benchmark exercises the Wakamex worker protocol in isolation. It is useful for fast regression testing of scheduling, cancellation, parsing, descriptor handling, and theme-specific correctness.

The comparative benchmark runs 14 representative configurations in real interactive terminals. It compares portable user-visible behavior across raw Zsh, Wakamex, Oh My Zsh themes, Pure, and two Powerlevel10k configurations without assuming that they share an internal worker protocol.

## Focused Wakamex benchmark

The default adapter targets a sibling [`wakamex-zsh-theme`](https://github.com/wakamex/wakamex-zsh-theme) checkout. Theme loading and collector operations stay in the adapter, while the benchmark owns timing and assertions. A different asynchronous theme would need its own adapter and equivalent mappings for any protocol-specific checks.

The correctness fixture is created under `/var/tmp`. The benchmark host mounts `/tmp` as a RAM-backed filesystem, so using `/var/tmp` keeps the fixture on ordinary storage and avoids silently measuring a different filesystem path.

The CLI prints one `name=value` field per line. Its main latency fields are:

| Field | Measurement |
|---|---|
| `cached_prompt_ms` | Prompt rendering from cached state. |
| `git_identity_ms` | Repository and branch discovery. |
| `git_status_ms` | Complete synchronous Git collection. |
| `fixture_clean_status_ms` | Status collection in the clean fixture. |
| `fixture_dirty_status_ms` | Status collection with a tracked modification. |
| `fixture_staged_status_ms` | Status collection with a staged change. |
| `fixture_untracked_status_ms` | Status collection with an untracked file. |
| `async_schedule_ms` | Time spent starting and briefly watching a worker before returning control. |
| `async_ready_ms` | Time until the complete asynchronous result arrives. |
| `sync_wait_ms` | The bounded identity wait against a deliberately slow worker. |

Both `git_status_ms` and `async_ready_ms` are retained because a prompt can accept input quickly while leaving Git state stale for much longer.

The focused correctness checks cover these observed failure modes:

- Rapid prompts coalesce one refresh instead of repeatedly cancelling and starving Git status.
- `preexec` cancels work that became stale when a command started.
- Results for an old directory cannot repaint the current prompt.
- A changed asynchronous result repaints ZLE.
- The synchronous identity wait remains bounded when Git is slow.
- Repeated workers release their descriptors and process state.
- Closing a worker descriptor does not permanently redirect shell stderr.
- Staged, unstaged, and untracked state remain distinguishable.
- Background Git runs with `GIT_OPTIONAL_LOCKS=0` and avoids optional index writes.

## Test layers

`internal/run.zsh` replaces `zle` with a recording function for deterministic protocol tests. These checks exercise partial worker messages, stale-result rejection, refresh coalescing, forced timeouts, descriptor release, status parsing, and optional Git locks. They are fast and localize a failure to one state transition.

`tests/pty.zsh` starts an isolated interactive Zsh on a real pseudo-terminal. It exercises actual `zle -F` callback delivery and prompt repainting, then verifies stderr and `time` output, directory changes during active scans, live `preexec` cancellation, steady-state theme reload, hook counts, worker cleanup, and the terminal target of file descriptor 2.

The end-to-end self-test runs the complete CLI with a small fixture, requires every metric and correctness check, validates option handling, exercises the selectable direct-Git control, and runs the PTY assertions. Protocol edge cases remain deterministic rather than being driven through timing-sensitive terminal input.

## Comparative target selection

The default matrix contains raw Zsh, Wakamex, nine Oh My Zsh themes, Pure, Powerlevel10k's Pure-style preset, and Powerlevel10k's built-in no-user-config defaults. The [selection evidence](research/theme-selection.md) explains how architecture, public configuration counts, layout coverage, source inspection, and independent prompt implementations determined the matrix.

The dated [popularity snapshot](research/theme-popularity-2026-08-27.tsv), [complete OMZ usage sweep](research/omz-theme-usage-2026-08-27.tsv), [infrastructure cutoffs](research/infra-cutoffs.md), and [direct Git inspection](research/direct-git-inspection-2264a8042763.md) retain the evidence behind that selection.

## External target preparation

The default matrix pins Pure v1.27.1 and Powerlevel10k v1.20.0. `powerlevel10k-pure` loads the bundled Pure-style preset. `powerlevel10k-fallback` disables the configuration wizard and exercises the built-in defaults used when no user configuration is present.

By default, the runner uses sibling Wakamex, Pure, and Powerlevel10k checkouts plus the Oh My Zsh checkout in `$ZSH` or `~/.oh-my-zsh`. Prepare the external siblings once:

```zsh
git clone --branch v1.27.1 --depth 1 https://github.com/sindresorhus/pure.git ../pure
git clone --branch v1.20.0 --depth 1 https://github.com/romkatv/powerlevel10k.git ../powerlevel10k
GITSTATUS_CACHE_DIR=../powerlevel10k/gitstatus/usrbin \
  sh ../powerlevel10k/gitstatus/install -f
```

Use `--pure`, `--pure-commit`, `--powerlevel10k`, `--powerlevel10k-commit`, and `--powerlevel10k-gitstatusd` when those pinned sources or the daemon live elsewhere. Pure runs with background fetch disabled so the comparison remains offline. Both Powerlevel10k targets verify the supplied daemon against the pinned source manifest, and accepted metadata records its SHA-256.

## Exploratory and accepted runs

Direct invocation is useful while developing the runner or inspecting one target:

```zsh
./research/benchmark-core-themes.zsh
./research/benchmark-core-themes.zsh > research/core-theme-benchmark-$(date +%F).tsv
./research/benchmark-core-themes.zsh --iterations 20 --samples-output /var/tmp/core-theme-samples.tsv --telemetry-output /var/tmp/core-theme-telemetry.tsv > /var/tmp/core-theme-summary.tsv
```

`--samples-output` writes one row for every target, state, and iteration. `--telemetry-output` records host load and Linux CPU-pressure snapshots at the start and end of every target. Standard output retains the median summary and the untimed staged and detached-HEAD semantic results.

Use the wrapper for a publishable run:

```zsh
./research/run-core-theme-benchmark.zsh \
  --output research/core-theme-run-$(date -u +%Y%m%dT%H%M%SZ) \
  -- --iterations 20
```

The wrapper requires a clean tracked worktree, calibrates the PTY reader before and after the matrix, checks provenance and artifact counts, enforces the CPU-pressure threshold, and publishes the run directory only after every gate passes. `--allow-dirty` exists for development smoke tests and is recorded in metadata.

## Interactive terminal boundary

Every target starts in a fresh `zsh -dfi` attached to a pseudo-terminal. The same shell is then reused for that target's state transitions and iterations. Commands enter through the terminal, and prompt markers emitted through ZLE delimit the first editable prompt and later repaints.

The runner waits on the PTY master descriptor and timestamps each read when it arrives. It does not poll on a fixed interval. This path includes shell hooks, `zle -F` callbacks, asynchronous repaints, command echo, and terminal state.

TSV latency fields have 0.001 ms numeric precision, but numeric precision is not measurement accuracy. Scheduler-dependent reader lateness is measured separately through the timing calibration.

## Repository states and sample sequencing

Every target sees the same temporary 1,000-file Git repository in clean, tracked-dirty, and untracked states. Before a recorded sample, an unrecorded prompt settles the opposite state so repaint counts describe a real state transition rather than a repeated no-op prompt.

For every timed sample the runner records time to the first editable prompt, time to the final prompt repaint, repaint count, Git process count, Git calls missing `GIT_OPTIONAL_LOCKS=0`, and the rendered semantic result. It waits for observed Git processes to exit and for a configurable quiet period before starting the next sample, preventing one asynchronous scan from being charged to the following command.

After each timed sample, the runner expands the target's actual `PROMPT` and `RPROMPT` outside the timing window and checks the rendered branch and worktree state. Existing theme formatting variables receive distinct labels so states are unambiguous without replacing collectors or prompt hooks.

After the timed matrix, the same shell performs one staged and one detached-HEAD transition. These scenarios affect correctness but do not add latency samples or alter the clean, dirty, and untracked medians.

## Direct Git control

The selectable `direct-git` control runs the same single scan used by the Wakamex collector through the comparative PTY transition path:

```zsh
GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 --branch --untracked-files=normal --ignore-submodules=dirty
```

Comparing it with `raw` isolates direct scan cost before attributing additional latency to worker transport, parsing, snapshot publication, or repainting. It remains outside the historical 14-target matrix and is selected explicitly with `--target raw --target direct-git`.

## Process and lock observation

The runner observes Git processes created during each transition and records how many omit `GIT_OPTIONAL_LOCKS=0`. It waits for those processes to exit before advancing. This distinguishes themes that return an editable prompt before background work finishes from themes that put all Git work on the input path.

Powerlevel10k may show zero observed Git child processes because its collection work occurs inside the resident `gitstatusd` process. Zero child processes therefore describes the measured boundary rather than zero collection cost.

## CPU pressure

The runner records epoch timestamps and Linux `/proc/pressure/cpu` `some total` cumulative counters immediately before and after every sample. The interval includes the quiet period used to confirm the final repaint. A counter increase proves that system-wide CPU pressure overlapped the observation window, but it does not identify the benchmark as the stalled task.

The accepted-run wrapper recalculates overlap for every retained sample and rejects a run when the median overlap exceeds 5 percent. CPU pressure remains an acceptance and diagnostic signal rather than a correction applied to latency values.

## Timing calibration

`tests/timing.zsh` keeps one PTY producer alive and generates events after nominal 5, 20, and 50 ms delays. Each event carries its producer timestamp, which is compared with the timestamp recorded after the runner reads it.

The standalone timing test rejects observation error above 2 ms. An accepted run uses 10 events per delay before and after the matrix, requires p90 observation error at or below 0.5 ms, caps every event at 5 ms, and records the median, p90, and maximum.

## Accepted artifacts and provenance

An accepted run contains `summary.tsv`, `samples.tsv`, `telemetry.tsv`, and `metadata.txt`. Metadata records the configuration, online CPU count, source identities, runner and artifact hashes, Powerlevel10k daemon hash, observed CPU-pressure median and limit, and both calibration results. The wrapper validates expected row counts and atomically renames its staging directory only after acceptance.

OMZ targets load the complete framework from the pinned commit recorded in the results. Wakamex loads directly from its recorded theme commit, Pure and Powerlevel10k use their pinned sources, and `raw` is an unthemed Zsh control. Load measurements include these different integration scopes, so command-to-prompt measurements are the more portable comparison.

## Summaries, reports, and grades

Derive median, p10, p90, maximum, repaint, process, lock, and semantic summaries from an accepted sample file without rerunning the matrix:

```zsh
./research/summarize-core-theme-samples.zsh research/core-theme-run-TIMESTAMP/samples.tsv
```

Generate the report from an accepted run:

```zsh
./research/generate-core-theme-report.zsh \
  research/core-theme-run-TIMESTAMP \
  research/core-theme-benchmark-$(date -u +%F).md
```

The generator verifies accepted artifact hashes, reproduces dispersion from raw samples, recalculates CPU-pressure overlap, and writes the report atomically. Mechanistic latency, process, and lock grades come from retained measurements.

Correctness grades are reviewed judgments tied to the five semantic outcomes in [`core-theme-correctness-assessment.tsv`](research/core-theme-correctness-assessment.tsv). Scope, missed infrastructure, narrative explanations, and explicit grade exceptions live in [`core-theme-report-annotations.tsv`](research/core-theme-report-annotations.tsv). Generation stops when an outcome changes or becomes mixed until the assessment is reviewed.
