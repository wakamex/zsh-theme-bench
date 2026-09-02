# Prompt-theme infrastructure cutoffs

Snapshot date: 2026-08-27

These dates help interpret [`omz-theme-metadata-2264a8042763.tsv`](omz-theme-metadata-2264a8042763.tsv).
They are review boundaries, not automatic evidence that a theme is stale.
`last_commit_at` is the last commit that touched the theme file, which may be a cosmetic or bulk edit.
The commit subject is retained so the touch can be reviewed.

## Cutoffs to mark in theme-age results

| Date | Change | Why it belongs on a theme-age result |
| --- | --- | --- |
| 2020-07-06 | Oh My Zsh routed its shared prompt helpers through `GIT_OPTIONAL_LOCKS=0` and removed several subprocesses from Git status parsing. | Current OMZ supplies the safer shared functions at runtime, so a theme can benefit without changing its own file. Direct Git calls bypass them. |
| 2022-02-12 | Zsh 5.8.1 fixed CVE-2021-45444 by stopping `PROMPT_SUBST` evaluation inside prompt-expansion arguments such as `%F`. | A crafted Git branch name could execute code under affected prompt configurations on older Zsh. This is a runtime security floor, not a request to rewrite every older theme. |
| 2022-03-24 | Git 2.35.2 added repository ownership checks and `safe.directory` as part of CVE-2022-24765. Git 2.35.3 followed on 2022-04-13 with fixes to `safe.directory` parsing and the `*` opt-out. | Git-enabled prompts can now reject a repository owned by another user and silently lose their Git segment if stderr is suppressed. The original Git fix explicitly identified an enabled `PS1` as an attack path. |
| 2024-04-03 | Oh My Zsh removed a blocking read from the async callback introduced on 2024-03-07. | Use this as the practical async-adoption marker. Current OMZ registers literal shared-helper calls found in prompt variables without requiring a theme-file update. Direct calls and nested helpers missed by that scan remain synchronous. |

The exact upstream changes are the Oh My Zsh [`GIT_OPTIONAL_LOCKS` wrapper](https://github.com/ohmyzsh/ohmyzsh/commit/1c58a746af7a67f311ee47f97285a855eaf18b5e), the [Zsh 5.8.1 prompt-expansion fix](https://zsh.sourceforge.io/releases.html), Git's [`safe.directory` ownership check](https://github.com/git/git/commit/8959555cee7ec045958f9b6dd62e541affb7e7d9), the [initial OMZ async Git prompt](https://github.com/ohmyzsh/ohmyzsh/commit/083cc2c8e8742bab8cce8c73a3e96f398e6b2da7), and its [nonblocking callback fix](https://github.com/ohmyzsh/ohmyzsh/commit/b43b84abc77850a3734c127c38afdd7cf7739dc6).

## Runtime capabilities to note separately

| Date | Release or change | Relevance |
| --- | --- | --- |
| 2014-08-29 | Zsh 5.0.6 | Current OMZ enables its async Git path by default only on Zsh 5.0.6 or newer. OMZ imposed this compatibility floor in 2024 after failures on older Zsh. |
| 2015-08-30 | Zsh 5.1 | Zsh reports child-process, signal, descriptor, and memory-management fixes aimed at races and deadlocks. It also added `sysopen`. This is useful context for custom worker implementations, but it is not the current OMZ version gate. |
| 2017-10-30 | Git 2.15.0 | Git shipped `--no-optional-locks` and `GIT_OPTIONAL_LOCKS=0`, designed for background processes such as prompt status scans. OMZ adopted the environment variable in 2020. |
| 2018-01-17 | Git 2.16.0 | Git added the fsmonitor extension for working-tree scans, initially through Watchman. It affects prompt latency only when configured. |
| 2020-02-15 | Zsh 5.8 | Current OMZ forces an extra fork below Zsh 5.8 to work around broken Ctrl-C behavior. This is a runtime branch in the async implementation, not a theme-maintenance cutoff. |
| 2026-06-29 | Git 2.55.0 | Git added its built-in fsmonitor daemon on Linux. It can reduce status scan work when `core.fsmonitor=true`; merely installing Git 2.55 does not enable it. |

The release dates come from the projects' release pages or annotated upstream tags.
Supporting sources are the [Zsh release history](https://zsh.sourceforge.io/News/), [Zsh release notes](https://zsh.sourceforge.io/releases.html), Git's [`--no-optional-locks` introduction](https://github.com/git/git/commit/27344d6a6c8056664966e11acf674e5da6dd7ee3), [Git 2.16 release notes](https://github.com/git/git/blob/v2.16.0/Documentation/RelNotes/2.16.0.txt), and [Git 2.55 release notes](https://github.com/git/git/blob/v2.55.0/Documentation/RelNotes/2.55.0.adoc).

Zsh 5.9 changed `zstyle` pattern-specificity behavior on 2022-05-14.
That is worth a separate compatibility assertion for a theme that depends on competing style patterns, but it does not alter the Git worker, callback, or repaint paths measured here.
Zsh 5.9.1 and 5.9.2 are maintenance and minor releases with no prompt-specific infrastructure change identified in their release notes, so they are not promoted to cutoff markers.

## Snapshot findings

The metadata snapshot contains 142 themes.
Its lexical direct-call field is a candidate signal; the complete [source inspection](direct-git-inspection-2264a8042763.md) found 65 actual invocation sites in 28 of the 30 flagged themes:

- 108 call `git_prompt_info`.
  Of the 28 themes with actual direct invocation sites, 11 also call the shared helper.
- 114 were last touched before the 2024-04-03 marker, but 94 of those reference the shared helper.
  Current OMZ runs literal prompt references through its async implementation without requiring a theme-file update.
  Nested references still require inspection because registration can miss them.
- 18 themes last touched before 2024-04-03 connect actual direct calls to an active prompt or hook.
  The most common by the public configuration-count proxy are `avit` at 535, `refined` at 364, `gentoo` at 330, `bureau` at 269, and `steeef` at 248.
- `agnoster` was touched on 2025-06-09, but it still contains 11 direct Git calls and uses the synchronous shared `parse_git_dirty` helper.
  Its recent file date does not make its architecture asynchronous.

The count before each primary marker is:

| Marker | Themes with an earlier last file touch | Of those, shared helper | Of those, active direct Git |
| --- | ---: | ---: | ---: |
| 2020-07-06 OMZ optional locks | 68 | 60 | 4 |
| 2022-02-12 Zsh prompt security | 93 | 83 | 7 |
| 2022-03-24 Git ownership check | 98 | 83 | 12 |
| 2024-04-03 OMZ nonblocking async | 114 | 94 | 18 |

These columns overlap because a theme can use a shared helper and make additional direct Git calls.

## Applying the cutoffs

Use the metadata fields together:

- `uses_git_prompt_info=1` means the theme references a function supplied by current OMZ.
  A literal reference in a prompt variable is registered for the default async path when Zsh and configuration allow it.
  A nested reference can be missed by registration.
- `uses_parse_git_dirty=1` means current OMZ executes that helper through its optional-lock wrapper, but the call remains on the theme's synchronous rendering path unless the caller moves it elsewhere.
- `direct_git_calls>0` selects candidates for source inspection.
  It is a lexical count, so it can include data such as `zstyle ... enable git`, miss older quoting forms, and count dormant code.
  The completed [inspection](direct-git-inspection-2264a8042763.md) records the actual execution paths.
  Direct calls do not automatically inherit OMZ's wrapper or async worker.
- `uses_zle_fd_handler=1` and `uses_zsh_hooks=1` identify custom integration that deserves PTY coverage for callback delivery, repainting, cancellation, reload, descriptor cleanup, and stderr.
- A last commit subject showing formatting, documentation, URLs, or a bulk cleanup is not evidence of a functional prompt update.

For prioritization, combine public use, a pre-cutoff last file touch, and direct Git calls.
Also keep high-use recent themes such as `agnoster` when their current architecture directly exercises the latency or correctness behavior under test.

The snapshot host runs Zsh 5.9 and Git 2.55.0.
`core.fsmonitor` was unset in the benchmark, OMZ, and Wakamex repositories when this note was written, so Linux's new built-in fsmonitor was available but did not affect the collected timings.
