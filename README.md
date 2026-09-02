# zsh-theme-bench

`zsh-theme-bench` measures Zsh prompts as people experience them in an interactive terminal. It records how quickly a prompt accepts input, how long Git information takes to become current, whether repository state is displayed correctly, and how much Git process work each theme performs.

The repository includes a focused regression benchmark for the [Wakamex theme](https://github.com/wakamex/wakamex-zsh-theme) and a comparative runner for 14 representative Zsh theme configurations.

## Results

In the latest 14-way comparison, [Wakamex](https://github.com/wakamex/wakamex-zsh-theme) was the fastest theme that correctly displayed every tested Git state. Across 20 runs in a 1,000-file repository, every Wakamex update completed within 8.126 ms using a single background Git scan.

The other themes showed large differences in behavior. Some returned an editable prompt quickly but updated Git information later, while others ran several Git commands before accepting input and occasionally took more than 100 ms. Soliah displayed ordinary branches as detached, and steeef failed to notice common file changes.

See the [full benchmark report](research/core-theme-benchmark-2026-09-02.md) for the complete comparison, ratings, and retained results.

## Usage

Run the focused Wakamex benchmark:

```zsh
./zsh-theme-bench
./zsh-theme-bench --iterations 20 --repo /path/to/repository
./zsh-theme-bench --help
```

The default adapter expects a sibling `wakamex-zsh-theme` checkout and prints machine-readable `name=value` measurements and correctness checks.

Run an exploratory comparison of the core themes:

```zsh
./research/benchmark-core-themes.zsh
```

Create a publishable 20-iteration run with calibration, provenance, raw samples, and host telemetry:

```zsh
./research/run-core-theme-benchmark.zsh \
  --output research/core-theme-run-$(date -u +%Y%m%dT%H%M%SZ) \
  -- --iterations 20
```

Compare raw Zsh with one direct Git scan without running the full matrix:

```zsh
./research/benchmark-core-themes.zsh --target raw --target direct-git
```

External theme preparation, measurement boundaries, acceptance rules, artifact formats, and report generation are documented in [METHODOLOGY.md](METHODOLOGY.md).

## Tests

```zsh
zsh tests/self-test.zsh
zsh tests/pty.zsh
```

The self-test covers the CLI, deterministic worker behavior, the comparative runner, report validation, and the direct-Git control. The PTY suite exercises callback delivery, repainting, cancellation, reload cleanup, child-process cleanup, and terminal descriptor integrity in a real interactive Zsh.

## Documentation

- [METHODOLOGY.md](METHODOLOGY.md) defines what is measured and how a run is accepted.
- [The latest report](research/core-theme-benchmark-2026-09-02.md) presents the retained measurements and ratings.
- [Theme selection evidence](research/theme-selection.md) explains the architecture and popularity coverage behind the matrix.
- [Direct Git source inspection](research/direct-git-inspection-2264a8042763.md) traces theme-owned Git work into active prompt paths.
- [Infrastructure cutoffs](research/infra-cutoffs.md) records the Zsh, Git, and Oh My Zsh changes used to interpret theme history.
