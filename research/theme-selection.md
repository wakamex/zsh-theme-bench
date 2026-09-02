# Theme selection evidence

Snapshot date: 2026-08-27

Local source inspected: Oh My Zsh commit `2264a8042763edf2620cfe32d96b096e1f3d26aa` under Zsh `5.9 (x86_64-redhat-linux-gnu)`.

## Recommended benchmark matrix

Run this core set for comparative latency and PTY behavior:

| Target | Role in the matrix |
| --- | --- |
| Raw Zsh | Control for shell and PTY overhead with no theme or Git collector. |
| Wakamex | System under test. |
| Oh My Zsh `robbyrussell` | OMZ default, largest public configuration count, and the modern OMZ asynchronous `git_prompt_info` path. |
| Oh My Zsh `agnoster` | Largest sampled non-default bundled theme and a synchronous, multi-command Git implementation. |
| Oh My Zsh `bureau` | Fully synchronous custom collector with status, stash, ref, repository, and config probes. |
| Oh My Zsh `Soliah` | Nested shared helper that OMZ's literal async registration scan cannot see. |
| Oh My Zsh `steeef` | Cached synchronous collector with an invalidation gap after ordinary file-changing commands. |
| Oh My Zsh `apple` | Pure synchronous `vcs_info` control with no actual direct Git invocation sites. |
| Oh My Zsh `mortalscumbag` | Critical-path stress case with status and two full log ranges on every prompt. |
| Oh My Zsh `ys` | Popular bundled multi-line prompt using OMZ's shared Git helper. |
| Oh My Zsh `bira` | Multi-line prompt, right prompt, and several optional environment segments. |
| Pure | Native-Zsh asynchronous prompt and the closest independent worker and repaint comparison. |
| Powerlevel10k Pure | High-performance design using `gitstatusd` and aggressive caching, configured with its bundled Pure-style preset for a direct architectural comparison. |
| Powerlevel10k fallback | The built-in no-user-config defaults, which expose broader Git state and allow a bounded synchronous VCS wait before falling back to an asynchronous repaint. |

Use these in an extended compatibility run:

| Target | Additional coverage |
| --- | --- |
| Starship | Popular compiled cross-shell prompt with a different process and caching model. |
| Spaceship | Feature-heavy external Zsh prompt with substantial public use and repository interest. |

The core set is intentionally architecture-driven.
The complete direct-call inspection explains the selected synchronous, nested-helper, cache-invalidation, and indirect-`vcs_info` cases.
Running dozens of bundled themes would mostly repeat those paths while adding rendering variations.
`ys` and `bira` cover the two terminal layouts most likely to expose a PTY-only integration problem. Pure and Powerlevel10k Pure use matching Pure-style scope with different asynchronous collectors, which makes their command-to-settled-prompt behavior a direct architectural counterfactual. Powerlevel10k fallback isolates the cost and behavior of the broader built-in defaults without a wizard-generated user configuration.

Cross-theme comparisons should use portable observations: time to first editable prompt, time to settled Git state, command-to-prompt latency, stale repaint behavior, descriptor and process deltas, stderr integrity, and cleanup after reload.
Protocol-message checks remain adapter-specific because the themes do not share a worker protocol.

Run the local core matrix with:

```zsh
./research/benchmark-core-themes.zsh
```

The runner extracts pinned OMZ, Pure, and Powerlevel10k commits into temporary storage, starts every target in a fresh interactive PTY, and reuses that PTY for the target's state transitions and iterations. Powerlevel10k uses its bundled Pure-style configuration and a preinstalled `gitstatusd` executable whose version is checked against the pinned source manifest.
Progress goes to stderr and reusable TSV goes to stdout.
It measures load, first editable prompt, final repaint, repaint count, Git process count, calls made without `GIT_OPTIONAL_LOCKS=0`, and rendered branch and state semantics in clean, tracked-dirty, and untracked fixtures. After the timed matrix, it checks staged and detached-HEAD semantics once per theme without adding latency samples.
PTY readiness wakes the runner immediately, and each read is timestamped when it arrives.
Pass `--samples-output FILE` to preserve every timed iteration in long-form TSV while keeping the median summary on stdout. Each retained sample includes timestamps and Linux CPU PSI cumulative counters immediately before and after its PTY measurement. Pass `--telemetry-output FILE` to record load averages and Linux CPU-pressure values at the start and end of every target.

Publish an accepted 20-iteration run with:

```zsh
./research/run-core-theme-benchmark.zsh \
  --output research/core-theme-run-$(date -u +%Y%m%dT%H%M%SZ) \
  -- --iterations 20
```

The wrapper requires a clean tracked worktree, applies 10 pre-run and post-run calibration events at each nominal delay, requires p90 PTY read error at or below 0.5 ms, caps any single event at 5 ms, rejects median per-sample CPU PSI `some` overlap above 5%, verifies sample and telemetry counts plus source identity, and publishes the summary, raw samples, host telemetry, and metadata as one atomically renamed directory.

Use `summarize-core-theme-samples.zsh RUN/samples.tsv` to derive median, p10, p90, maximum, repaint, process, lock, and semantic summaries from the retained samples.

## OMZ popularity proxy

Oh My Zsh distributes more than 150 themes in one repository and does not expose separate install counts for them.
Its documentation identifies `robbyrussell` as the default and uses `agnoster` as the main alternative example.
See the [Oh My Zsh theme documentation](https://github.com/ohmyzsh/ohmyzsh#themes) and [default zshrc template](https://github.com/ohmyzsh/ohmyzsh/blob/master/templates/zshrc.zsh-template).

I queried GitHub's REST code-search endpoint for public files containing each candidate `ZSH_THEME="name"` assignment.
Among the 19 bundled candidates sampled, the largest totals were:

| Theme or selector | Public code-search total |
| --- | ---: |
| `robbyrussell` | 21,280 |
| `agnoster` | 7,600 |
| `random` | 1,572 |
| `ys` | 1,272 |
| `bira` | 928 |
| `af-magic` | 878 |
| `avit` | 535 |

`random` is a selector rather than a stable theme, so it is not a useful comparative target.
The selected cross-project snapshot is in [`theme-popularity-2026-08-27.tsv`](theme-popularity-2026-08-27.tsv), and the complete OMZ theme sweep is in [`omz-theme-usage-2026-08-27.tsv`](omz-theme-usage-2026-08-27.tsv).

This proxy covers public indexed files, including forks, templates, and stale dotfiles.
It does not measure active installations, and the default template inflates `robbyrussell`.
It is still useful for deciding which bundled themes deserve compatibility coverage.
Repository stars answer a different question: project awareness rather than actual prompt use.

## External prompt signal

Current GitHub repository stars provide a rough independent signal for external prompts:

| Prompt | Stars |
| --- | ---: |
| [Starship](https://github.com/starship/starship) | 59,631 |
| [Powerlevel10k](https://github.com/romkatv/powerlevel10k) | 54,982 |
| [Spaceship](https://github.com/spaceship-prompt/spaceship-prompt) | 20,566 |
| [Pure](https://github.com/sindresorhus/pure) | 14,400 |

These four are useful because each represents a distinct implementation, not because their star counts are directly comparable with OMZ code-search totals.

## Reproduction and API choice

The repeatable collector discovers every `.zsh-theme` file in a pinned local OMZ checkout, queries the exact double-quoted assignment, paces requests, and appends each result immediately to a TSV:

```sh
./research/sweep-omz-theme-usage.zsh
```

[`sweep-omz-theme-usage.zsh`](sweep-omz-theme-usage.zsh) resumes existing output automatically and records the query, timestamp, OMZ commit, result count, and `incomplete_results` flag.
Its default 6.5-second delay stays below the REST code-search limit of 10 authenticated requests per minute.
Use `--help` to select another OMZ checkout, output path, delay, or a small theme limit.

The history collector derives immutable metadata from the pinned OMZ commit and appends one theme at a time to a commit-addressed TSV:

```sh
./research/collect-omz-theme-metadata.zsh
```

[`collect-omz-theme-metadata.zsh`](collect-omz-theme-metadata.zsh) requires a full, non-shallow OMZ history.
It records the last commit date, SHA, and subject along with references to `git_prompt_info`, `parse_git_dirty`, `vcs_info`, direct Git command counts, ZLE descriptor handlers, and Zsh hooks.
It reads both the theme list and source from the pinned commit, so local working-tree changes do not alter the results.
The direct-call count is a lexical candidate signal rather than a shell parser.
The [manual source inspection](direct-git-inspection-2264a8042763.md) follows all 30 flagged themes into their prompt and hook paths and records false positives, dormant code, timing, and shared-helper interactions.

The relevant Zsh, Git, and Oh My Zsh dates and the rules for applying them are recorded in [`infra-cutoffs.md`](infra-cutoffs.md).
The note separates theme-age markers from runtime and configuration capabilities so an old theme file is not mistaken for an old shared helper.

GitHub GraphQL is useful for batching repository metadata such as star counts after repository names are known.
Schema introspection on the snapshot date returned `ISSUE`, `REPOSITORY`, `USER`, and `DISCUSSION` search types, plus issue-specific variants, but no code search type.
It therefore cannot replace REST for searching `ZSH_THEME` assignments in file bodies.
GitHub's private code-search RPC may provide counts with less rate-limit friction, but it is undocumented and is not needed for this small snapshot.

Modern OMZ behavior should be pinned when comparative adapters are implemented.
Its [`git.zsh`](https://github.com/ohmyzsh/ohmyzsh/blob/master/lib/git.zsh) enables asynchronous Git prompt evaluation by default on supported Zsh versions, while themes such as [`agnoster`](https://github.com/ohmyzsh/ohmyzsh/blob/master/themes/agnoster.zsh-theme) also invoke additional Git commands directly.
