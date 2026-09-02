# zsh-theme-bench

`zsh-theme-bench` measures asynchronous Zsh prompt behavior that ordinary startup and command-lag benchmarks miss.
It was built while debugging the Wakamex theme and borrows zsh-bench's practice of running repeated measurements in an isolated shell.

The default adapter targets a sibling `wakamex-zsh-theme` checkout.
The adapter keeps theme loading and basic collector operations in one place.
The correctness probes exercise Wakamex's current worker protocol, so a different asynchronous theme would need an adapter plus equivalent protocol mappings.

## Usage

```zsh
./zsh-theme-bench
./zsh-theme-bench --iterations 20 --repo /path/to/repository
./zsh-theme-bench --help
```

The benchmark creates its Git correctness fixture under `/var/tmp`, not `/tmp`.
This host mounts `/tmp` as a 16 GB RAM-backed tmpfs, while `/var/tmp` has normal disk capacity.

Output is one `name=value` field per line:

```text
cached_prompt_ms=0.031
git_identity_ms=0.082
git_status_ms=8.421
fixture_clean_status_ms=7.902
fixture_dirty_status_ms=8.104
fixture_staged_status_ms=8.066
fixture_untracked_status_ms=8.331
async_schedule_ms=1.204
async_ready_ms=9.733
sync_wait_ms=3.107
fd_delta=0
check_stderr_preserved=1
```

The latency fields separate work on the prompt's critical path from background freshness:

- `cached_prompt_ms` measures prompt rendering from cached state.
- `git_identity_ms` measures repository and branch discovery.
- `git_status_ms` measures the complete synchronous Git collector.
- `fixture_*_status_ms` compares clean, tracked-dirty, staged, and untracked scans in the same fixture.
- `async_schedule_ms` measures how long the prompt waits while starting and briefly watching a worker.
- `async_ready_ms` measures how long the complete asynchronous result takes to arrive.
- `sync_wait_ms` measures the configured 3 ms identity deadline against a deliberately slow worker.

The checks cover failures observed while building the theme:

- Rapid prompts coalesce one refresh instead of repeatedly cancelling and starving Git status.
- `preexec` cancels work that became stale when a command started.
- Results for an old directory cannot repaint the current prompt.
- An asynchronous result repaints ZLE when visible state changes.
- The synchronous identity wait remains bounded when Git is slow.
- Repeated workers release their descriptors and process state.
- Closing a worker descriptor does not permanently redirect shell stderr.
- Staged, unstaged, and untracked state remain distinguishable.
- Background Git runs with `GIT_OPTIONAL_LOCKS=0` and avoids optional index writes.

The benchmark reports both `git_status_ms` and `async_ready_ms` because a theme can have excellent command latency while showing Git state seconds late in a very large repository.

## Tests

```zsh
zsh tests/self-test.zsh
zsh tests/pty.zsh
```

The tests use two layers because the asynchronous protocol and the interactive terminal have different failure modes.

`internal/run.zsh` replaces `zle` with a recording function.
These deterministic checks exercise partial worker messages, stale-result rejection, refresh coalescing, forced timeouts, descriptor release, status parsing, and optional Git locks.
They are fast, and a failure points at one function or state transition.

`tests/pty.zsh` starts an isolated interactive Zsh on a real pseudo-terminal.
It exercises actual `zle -F` callback delivery and prompt repainting, then verifies stderr and `time` output, a directory change during an active scan, live `preexec` cancellation, steady-state theme reload, hook counts, worker child-process cleanup, and the terminal target of file descriptor 2.

The PTY suite intentionally does not replace the deterministic checks.
Driving every protocol edge case through terminal input would make failures slower, timing-sensitive, and harder to localize.
The end-to-end self-test runs the complete CLI with a small fixture, requires every metric and correctness check, validates option handling, and then runs the PTY suite.

## Comparative targets

The proposed cross-theme matrix and the evidence used to choose it are in [`research/theme-selection.md`](research/theme-selection.md).
The dated GitHub code-search and repository-star snapshot is available as [`research/theme-popularity-2026-08-27.tsv`](research/theme-popularity-2026-08-27.tsv).
The infrastructure dates used to interpret OMZ theme history are in [`research/infra-cutoffs.md`](research/infra-cutoffs.md).
The follow-up inspection of every theme flagged for direct Git calls is in [`research/direct-git-inspection-2264a8042763.md`](research/direct-git-inspection-2264a8042763.md).
Run the selected core themes in isolated interactive PTYs with [`research/benchmark-core-themes.zsh`](research/benchmark-core-themes.zsh).

The default matrix includes Pure v1.27.1 and two Powerlevel10k v1.20.0 configurations at immutable commits. `powerlevel10k-pure` loads the bundled Pure-style preset, while `powerlevel10k-fallback` exercises Powerlevel10k's built-in no-user-config defaults with its configuration wizard disabled. By default, the runner uses a sibling Wakamex, Pure, and Powerlevel10k checkout, plus the Oh My Zsh checkout in `$ZSH` or `~/.oh-my-zsh`. Prepare the external sibling checkouts once:

```zsh
git clone --branch v1.27.1 --depth 1 https://github.com/sindresorhus/pure.git ../pure
git clone --branch v1.20.0 --depth 1 https://github.com/romkatv/powerlevel10k.git ../powerlevel10k
GITSTATUS_CACHE_DIR=../powerlevel10k/gitstatus/usrbin \
  sh ../powerlevel10k/gitstatus/install -f
```

Use `--pure`, `--pure-commit`, `--powerlevel10k`, `--powerlevel10k-commit`, and `--powerlevel10k-gitstatusd` when the pinned checkouts or daemon live elsewhere. Pure runs with background fetch disabled so the comparison remains offline. Both Powerlevel10k targets validate the supplied daemon version against the pinned source manifest, and accepted-run metadata records the daemon SHA-256. The fallback target is not a configuration-wizard preset: it records the internal defaults used when no user configuration is loaded.

```zsh
./research/benchmark-core-themes.zsh
./research/benchmark-core-themes.zsh > research/core-theme-benchmark-$(date +%F).tsv
./research/benchmark-core-themes.zsh --iterations 20 --samples-output /var/tmp/core-theme-samples.tsv --telemetry-output /var/tmp/core-theme-telemetry.tsv > /var/tmp/core-theme-summary.tsv
```

Direct invocation is useful for exploratory runs. `--samples-output` writes one long-form row for every target, repository state, and iteration, including timestamps and Linux CPU PSI cumulative counters that bracket the measurement. `--telemetry-output` writes host load averages and Linux CPU-pressure snapshots at the start and end of every target while stdout retains the median summary plus untimed staged and detached-HEAD semantic results.

Use the accepted-run wrapper for a publishable run:

```zsh
./research/run-core-theme-benchmark.zsh \
  --output research/core-theme-run-$(date -u +%Y%m%dT%H%M%SZ) \
  -- --iterations 20
```

The wrapper requires a clean tracked worktree, calibrates the complete PTY read path immediately before and after the matrix, validates provenance and the expected sample and telemetry counts, rejects median per-sample CPU PSI `some` overlap above 5%, and atomically renames one run directory into place only after every gate passes. The directory contains `summary.tsv`, `samples.tsv`, `telemetry.tsv`, and `metadata.txt`; metadata records configuration, online CPU count, the observed PSI median and limit, source hashes, artifact hashes, and both calibration results. `--allow-dirty` exists for development smoke tests, and the metadata records its use.

Generate median, p10, p90, and maximum latency plus median repaint and process counts from an accepted run without rerunning it:

```zsh
./research/summarize-core-theme-samples.zsh research/core-theme-run-TIMESTAMP/samples.tsv
```

Generate a report from an accepted run without carrying forward stale measurements or judgments:

```zsh
./research/generate-core-theme-report.zsh \
  research/core-theme-run-TIMESTAMP \
  research/core-theme-benchmark-$(date -u +%F).md
```

The generator verifies accepted artifact hashes, reproduces dispersion from raw samples, recalculates per-sample PSI overlap, and publishes the Markdown atomically. Mechanistic grades come from retained measurements. Manual correctness grades are tied to their five reviewed semantic outcomes in [`core-theme-correctness-assessment.tsv`](research/core-theme-correctness-assessment.tsv), while scope, missed infrastructure, explanations, and explicit exceptional grades live in [`core-theme-report-annotations.tsv`](research/core-theme-report-annotations.tsv). A changed or mixed semantic outcome stops generation until the correctness grade is reviewed.

The runner starts every target in a fresh `zsh -dfi` attached to a pseudo-terminal and reuses that shell for the target's state transitions and iterations.
It sends real commands through the terminal and observes prompt markers emitted by ZLE, so shell hooks, `zle -F` callbacks, asynchronous repaints, command echo, and terminal state follow the same path as an interactive session.
It waits on the PTY master descriptor and timestamps each read as it arrives instead of polling at a fixed interval.
TSV latency fields have 0.001 ms numeric precision, but scheduler-dependent PTY observation error is larger.
Function-level protocol tests remain separate because they make partial messages and failure transitions deterministic.

Each target sees the same temporary Git repository in clean, tracked-dirty, and untracked states.
Before each recorded sample, an unrecorded prompt settles the opposite repository state so repaint counts represent a real state transition rather than repeated no-op prompts.
The runner records the median time to the first editable prompt, time to the final prompt repaint, repaint count, Git process count, Git calls missing `GIT_OPTIONAL_LOCKS=0`, and the number of rendered prompt semantic checks that pass. The optional long-form output preserves the underlying first-prompt, settled-prompt, repaint, process, lock, and semantic result for every iteration. It also records epoch timestamps and `/proc/pressure/cpu` `some total` counters immediately before and after each recorded PTY measurement. The interval includes the quiet period used to confirm the final repaint. A counter increase shows that system-wide CPU pressure overlapped the observation window, but does not by itself prove that the benchmark process was the stalled task.
It also waits for every observed Git process to exit and for a configurable quiet period before starting the next sample, which prevents an asynchronous scan from being charged to the following command.
After each timed sample, it expands the target's actual `PROMPT` and `RPROMPT` outside the measurement window and checks the rendered branch plus clean, tracked-dirty, or untracked state.
Distinct labels supplied through existing theme formatting variables make states unambiguous without replacing their collectors or prompt hooks.
After all timed samples for a target, the runner performs one staged and one detached-HEAD transition through the same interactive shell and records their semantic pass or failure in the summary. These scenarios do not add latency samples or change the clean, dirty, and untracked medians. Correctness grades remain separate published analysis and are not revised automatically from an exploratory run.
`tests/timing.zsh` keeps one PTY producer alive, generates nominal 5, 20, and 50 ms events, and compares the producer's emission timestamp with the timestamp taken after the runner reads each event. Its standalone default rejects any observation error above 2 ms. The accepted-run wrapper uses 10 events per delay, requires p90 observation error at or below 0.5 ms, caps any single event at 5 ms, and records the median, p90, and maximum before and after the matrix.

OMZ targets load the complete framework from the pinned commit recorded in the TSV.
`wakamex` loads its theme directly from the recorded local commit, and `raw` is an unthemed Zsh control.
The load values therefore include different integration scopes; the command-to-prompt values are the portable comparison.

The selectable `direct-git` control runs the same single `git status --porcelain=v2 --branch --untracked-files=normal --ignore-submodules=dirty` scan used by the Wakamex collector, with `GIT_OPTIONAL_LOCKS=0`, through the same PTY transition path. Compare it with `raw` to isolate direct scan cost before attributing additional settled latency to provider transport, parsing, snapshot publication, or repainting. It remains outside the default historical theme matrix and can be requested with `--target raw --target direct-git`.
