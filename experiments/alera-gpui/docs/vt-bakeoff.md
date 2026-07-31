# VT Bakeoff

## Question

The terminal decision compared the published Rust `alacritty_terminal` crate with the prebuilt `libghostty-vt` already vendored for Alera. Both parsed the exact same deterministic 2,560,000-byte ANSI corpus at 120 columns by 40 rows in an optimized build.

## Command

```bash
cargo run --release --manifest-path experiments/alera-gpui/Cargo.toml --bin vt_bakeoff
```

`ALERA_GHOSTTY_VT_LIBRARY` can override the default vendored shared-library path.

## Result

| Engine | Median | p95 | Median Throughput |
| --- | ---: | ---: | ---: |
| `alacritty_terminal` 0.26 | 122.753 ms | 240.455 ms | 20.85 MB/s |
| `libghostty-vt` | 68.059 ms | 68.153 ms | 37.61 MB/s |

Ghostty was 1.80 times faster by median and substantially tighter at p95.

## Decision

Use `alacritty_terminal` for this POC because its Rust API exposes cells, modes and events directly and allowed the complete GPUI data path to be proven quickly. Keep `libghostty-vt` as the preferred production investigation because it won the parser benchmark and exposes modern terminal behavior such as richer keyboard, mouse and graphics protocols.

The tradeoff is API maturity. Ghostty describes `libghostty-vt` as usable and cross-platform but still evolving, and its C API does not supply GPUI rendering, selection, tabs or session management. Those layers remain Alera responsibilities. The POC therefore does not claim that swapping parsers alone produces a complete terminal.

## Zed Findings

Zed validates the broad architecture: PTY/session work is separated from terminal state and GPUI rendering, and Zed uses an Alacritty-derived terminal core. Useful concepts were studied, but the POC does not import Zed product crates or copy its terminal implementation. This avoids coupling Alera's experiment to Zed's application graph and keeps the proof focused on GPUI plus Alera's runtime.
