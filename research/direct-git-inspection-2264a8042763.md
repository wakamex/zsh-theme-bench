# Direct Git source inspection

Inspection date: 2026-08-27

Oh My Zsh source: commit `2264a8042763edf2620cfe32d96b096e1f3d26aa`

The metadata scan flagged 30 themes and reported 69 direct Git invocation sites.
I inspected every `git` occurrence in those files, followed its enclosing function into `PROMPT`, `RPROMPT`, or hook registration, and compared nested shared-helper calls with the async registration logic in the pinned OMZ `lib/git.zsh`.

The review found 65 actual direct invocation sites in 28 themes.
Of those, 27 themes connect at least one site to an active prompt or hook.
`apple` and `emotty` were false positives caused by `zstyle ... enable git`, while `wedisagree` defines three direct calls in an unused function.

An invocation site is one Git command written in the source.
Fallback chains and conditionals mean that not every site executes on every render.
None of the 65 direct sites calls OMZ's `__git_prompt_git` wrapper or sets `GIT_OPTIONAL_LOCKS=0`.
Calls made separately through shared OMZ helpers do use the wrapper.

The review started from this reproducible context listing:

```zsh
commit=2264a8042763edf2620cfe32d96b096e1f3d26aa
omz_dir=${ZSH:-$HOME/.oh-my-zsh}
while IFS=$'\t' read -r theme direct_sites; do
  (( direct_sites > 0 )) || continue
  print -r -- "===== $theme ====="
  git -C "$omz_dir" show "${commit}:themes/$theme.zsh-theme" | rg -n '\bgit\b'
done < <(tail -n +2 research/omz-theme-metadata-2264a8042763.tsv | cut -f3,9)
```

Each match was then traced through the full pinned theme source.
The context listing alone cannot establish reachability or timing.

## Per-theme inspection

| Theme | Reviewed direct sites | Trigger | Finding |
| --- | ---: | --- | --- |
| `agnoster` | 11 | Every prompt; 3 sites require `AGNOSTER_GIT_INLINE=true` | Synchronous config, repository, ref, and two complete ahead/behind `log` ranges run alongside `parse_git_dirty` and `vcs_info`. The default path repeats working-tree and repository discovery. |
| `apple` | 0 | `vcs_info` on every `precmd` | Scanner false positive from `zstyle ... enable git`. `vcs_info` still performs synchronous Git change detection. |
| `avit` | 1 | Every right-prompt render | A synchronous `git log -1` computes commit age while literal shared info and status helpers can use OMZ async. |
| `blinks` | 1 | Every prompt | A synchronous `rev-parse` chooses the prompt glyph and repeats repository detection already done by the shared info helper. |
| `bureau` | 6 | Every right-prompt render | Fully synchronous custom collector: ref or detached SHA, porcelain status, stash probe, repository probe, and config probe. It bypasses shared helpers and optional locks. |
| `dogenpunk` | 4 | Every prompt and right prompt | Synchronous `branch`, repository, commit-age `log`, and status probes run in addition to literal shared async info and status helpers. The scan missed the backtick `git log`. |
| `dstufft` | 1 | Every prompt | Synchronous `git branch` selects a glyph and duplicates the shared helper's repository detection. |
| `emotty` | 0 | `vcs_info` on every `precmd` | Scanner false positive from `zstyle ... enable git`. `vcs_info` still performs synchronous change detection. |
| `fino` | 1 | Every prompt | Synchronous `git branch` selects a glyph in addition to the shared info helper. |
| `fino-time` | 1 | Every prompt | Synchronous `git branch` selects a glyph in addition to the shared info helper. |
| `gentoo` | 1 | Every `precmd`, inside a `vcs_info` hook | A porcelain status scan searches for untracked files while `vcs_info` also has `check-for-changes` enabled. Both remain synchronous. |
| `half-life` | 1 | Initial prompt, directory change, or after a command containing `git` or `svn` | `ls-files` and `vcs_info` are cached behind `PR_GIT_UPDATE`. A file-changing command such as `touch` does not invalidate the cache, so the prompt can remain stale. |
| `jnrowe` | 2 | Every `precmd` | After synchronous `vcs_info`, staged and then unstaged `git diff` probes choose a glyph. The second probe is skipped when staged changes exist; untracked state is not checked. |
| `josh` | 1 | Every prompt when a branch exists | A direct synchronous status scan follows the shared synchronous `git_current_branch` helper. The direct scan bypasses optional locks. |
| `kolo` | 1 | Every `precmd` | `ls-files` checks untracked files and then `vcs_info` performs its own synchronous change detection. |
| `linuxonly` | 2 | Every `precmd` | Same staged-then-unstaged synchronous diff chain as `jnrowe`, after `vcs_info`. |
| `lukerandall` | 1 | Every prompt | A synchronous `symbolic-ref` hides the segment on detached HEAD. `git_prompt_status` is nested inside `my_git_prompt_info`, so OMZ's literal prompt scan does not register its default async status handler. |
| `mortalscumbag` | 4 | Every prompt | A synchronous repository probe, porcelain status, and two full `git log` ranges run on every render. The log ranges repeatedly call `git_current_branch`, assume `origin/<branch>`, and materialize commit output only to grep it. |
| `peepcode` | 3 | Every right-prompt render in a branch | Synchronous repository, short-SHA, and modified-file probes follow `git_current_branch`. Dirty detection ignores untracked and staged-only changes. |
| `refined` | 2 | Every `precmd` | `rev-parse` and `git diff --quiet HEAD` run synchronously after `vcs_info`. The diff includes tracked staged and unstaged changes but ignores untracked files. |
| `rixius` | 1 | Every prompt | Synchronous `git branch` selects a glyph and duplicates shared helper repository detection. |
| `rkj-repos` | 3 | Every prompt | Synchronous config and ref/SHA probes wrap shared short-SHA and status helpers. The nested `git_prompt_status` call is invisible to OMZ's default async registration scan, so status output is not registered by this theme alone. |
| `smt` | 3 | Every prompt and right prompt | Synchronous branch, commit-age `log`, and status calls run alongside literal shared info and status helpers. The direct status duplicates the shared status scan. |
| `Soliah` | 4 | Every prompt | Two repository probes, commit-age `log`, and status run synchronously. The scan missed the backtick `git log`. Nested `git_prompt_info` calls are invisible to OMZ's default async registration scan, so the theme can label an ordinary repository `detached-head` when no other component registers the handler. |
| `steeef` | 1 | Initial prompt, directory change, or after a command containing `git`, `hub`, or `svn` | `ls-files` and `vcs_info` use the same limited invalidation cache as `half-life`; unrelated commands that modify files can leave stale Git state. |
| `sunrise` | 2 | Every prompt in a branch | Direct symbolic-ref and porcelain status run with synchronous shared `parse_git_dirty` and `git_prompt_ahead`. It performs two working-tree status scans per render. |
| `suvash` | 1 | Every prompt | Synchronous `git branch` selects a glyph and duplicates shared helper repository detection. |
| `trapd00r` | 2 | Every `precmd` | Same staged-then-unstaged synchronous diff chain as `jnrowe`, after `vcs_info`. |
| `wedisagree` | 3 | Dormant | Repository, commit-age `log`, and status calls exist only in `git_time_since_commit`, which is never referenced by this theme's prompt or hooks. The scan missed the backtick `git log`. |
| `zhann` | 1 | Every `precmd` | `ls-files` checks untracked files and then `vcs_info` performs its own synchronous change detection. |

## Findings for the benchmark matrix

- The lexical count is a useful candidate filter, but not an authoritative call count.
  It treated some `zstyle ... enable git` values as commands, missed three backtick commands, and could not identify dormant code.
- All 27 themes with active direct calls put at least some Git work on a synchronous prompt or `precmd` path.
  `half-life` and `steeef` cache that work, but their invalidation misses ordinary file-changing commands.
- `Soliah`, `lukerandall`, and `rkj-repos` call shared async helpers behind theme wrappers.
  OMZ only registers a handler when the literal `$(git_prompt_info)` or `$(git_prompt_status)` appears in a prompt variable, so the nested helpers are not registered by those themes alone.
- `agnoster`, `bureau`, and `mortalscumbag` provide the clearest repeated-probe and critical-path latency cases.
  `agnoster` remains the best high-use representative.
- `Soliah` provides the sharpest nested-async correctness case.
  `half-life` or `steeef` provides the sharpest stale-cache case.
- Direct working-tree status calls without OMZ's optional-lock wrapper occur in `bureau`, `dogenpunk`, `gentoo`, `josh`, `mortalscumbag`, `smt`, `Soliah`, and `sunrise`.
  `wedisagree` contains another such call only in dormant code.
- Several `vcs_info` themes have no direct status command but still request synchronous `check-for-changes`.
  A direct-call filter alone cannot classify total Git latency.

The inspection does not convert a source finding into timing evidence.
Comparative benchmark runs should measure the selected themes in the same repositories and use PTY assertions for nested async registration, stale state, repainting, and stderr behavior.
