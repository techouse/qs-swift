# QsBench

A tiny, standalone benchmark harness for the `Qs` library. It lets you compare baseline builds vs. builds with optional inlining or other compile-time flags, and quickly see whether micro–optimizations are worth it.

---

## What it benchmarks

Two simple scenarios:

- **list** – builds a large query string like `a[]=0,1,2&a[]=1,2,3…`, stressing comma-split parsing + decode.
- **deep** – builds a *very* deep key path like `foo[p][p]...[p]=x`, stressing key–segment splitting and object assembly.

You can tweak these inputs in `Sources/QsBench/main.swift`.

---

## Prerequisites

- Swift 5.9+ toolchain (SwiftPM)
- macOS or Linux shell
- (Optional) [hyperfine](https://github.com/sharkdp/hyperfine) for nicer A/B comparisons
  - macOS: `brew install hyperfine`
  - Debian/Ubuntu: `sudo apt-get install hyperfine`

The provided `Makefile` also exports `SWIFT_DETERMINISTIC_HASHING=1` so runs are stable across processes.

---

## Quick start

```bash
cd Bench

# Build (release)
swift build -c release

# Run the default scenario (list)
.build/release/QsBench list

# Run the deep scenario with a larger depth
N=5000 .build/release/QsBench deep
```

You should see the “work” result (count/boolean) and elapsed time printed.

---

## A/B profiling with hyperfine

The repo includes `scripts/profile.sh`, which:

1. Builds a **baseline** release and saves it as `QsBench_base`
2. Builds an **inline** variant with `-DQSBENCH_INLINE` and saves it as `QsBench_inline`
3. Benchmarks both with `hyperfine` for **list** and **deep**

Run it via the `Makefile`:

```bash
make profile
```

or directly:

```bash
bash scripts/profile.sh
```

> Tip: The `QSBENCH_INLINE` flag is used inside the benchmark code to toggle “hot path” annotations (`@inline(__always)`/`@inlinable`) so you can verify they actually help.

---

## Interpreting results

`hyperfine` prints mean ± σ and range. Differences within ~1–3% are usually noise on a modern laptop. Look for consistent wins across 20+ runs before committing micro-optimizations.

To reduce noise:

- Close background apps; keep CPU frequency stable (plugged in, low thermal load).
- Run multiple times; consider `--warmup 3 -r 20` (already used in the script).

---

## Instruments / Time Profiler (optional)

If you want call-level hotspots:

```bash
# Time Profiler from CLI (macOS)
instruments -t "Time Profiler" .build/release/QsBench --args list
```

Or open Instruments.app and select the `QsBench` binary manually.

---

## Makefile helpers

```bash
make help     # list targets
make clean    # clean SwiftPM artifacts
make reset    # clean + reset package
make profile  # run A/B hyperfine script
```

---

## Why this is a separate package

Benchmarks are **not** shipped with the main library product. Keeping them in `Bench/` (their own Swift package) avoids pulling benchmark code or flags into your app/library builds.

---

## Customizing workloads

Open `Sources/QsBench/main.swift` and adjust:

- For **list** scenario:
  - the shape and size of `parts` and the delimiter behavior
- For **deep** scenario:
  - the depth `N` (via `N=...`) and the segment name

Then rebuild and re-run:

```bash
swift build -c release
.build/release/QsBench list
```

Happy profiling!
