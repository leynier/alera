# Alera GPUI POC

This experiment is a Linux-first alternative desktop client for the existing Alera runtime. It must remain isolated from Flutter release builds and must never open `runtime.sqlite` directly.

## Outcome

The POC validates the architecture and passes the terminal performance gate. It is a staged-migration proof, not a production replacement. Start with the [feasibility conclusion](docs/feasibility.md), then read the [architecture](docs/architecture.md), [feature matrix](docs/feature-matrix.md), [performance evidence](docs/performance.md), [VT bakeoff](docs/vt-bakeoff.md) and [implementation plan](docs/implementation-plan.md).

## Development

Run against the active managed Alera runtime:

```bash
cargo run --manifest-path experiments/alera-gpui/Cargo.toml
```

The client reads `ALERA_RUNTIME_DIR` when present and otherwise uses the default Alera runtime directory.

Compile the alternate Linux backend:

```bash
cargo check --manifest-path experiments/alera-gpui/Cargo.toml --no-default-features --features x11 --bin alera-gpui
```

Run the live, read-only runtime contract smoke:

```bash
cargo run --manifest-path experiments/alera-gpui/Cargo.toml --bin runtime_smoke
```

Run performance modes after one release build:

```bash
cargo build --release --manifest-path experiments/alera-gpui/Cargo.toml --bin terminal_performance
ALERA_GPUI_BENCH_MODE=stream experiments/alera-gpui/target/release/terminal_performance
ALERA_GPUI_BENCH_MODE=idle experiments/alera-gpui/target/release/terminal_performance
ALERA_GPUI_BENCH_MODE=restore experiments/alera-gpui/target/release/terminal_performance
```

## Reuse provenance

- `gpui` and `gpui_platform`: Zed Industries.
- `gpui-component`: Longbridge.
- `alacritty_terminal`: published terminal-state crate used by this POC.
- `libghostty-vt`: vendored binary used only by the reproducible bakeoff.
- Zed product crates are architecture references only and are not linked into this POC.
