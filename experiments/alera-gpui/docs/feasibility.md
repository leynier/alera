# Feasibility Conclusion

## Verdict

Reimplementing Alera Desktop with GPUI is technically feasible and the architecture is a strong fit for Alera's existing Rust runtime host. The POC proves that GPUI can coexist with Flutter, consume the same live catalog and terminal sessions, reuse Alera's native Git/process boundaries, and reduce continuous terminal CPU far beyond the agreed threshold.

The recommendation is `Go` for a staged migration, not an immediate Flutter replacement. The proof removes the major architectural and performance uncertainty. It does not remove the product work needed for daily-driver terminal interaction, split layouts, accessibility, provider breadth, typed administration screens, packaging and non-Linux platforms.

## What The POC Proved

- One shared Rust runtime client supports correlated concurrent RPC, events, legacy newline frames and binary terminal frames without duplicating the protocol in GPUI.
- Flutter and GPUI can remain connected to one installed runtime host at the same time, and closing GPUI does not stop the host or Flutter.
- A recognizable Alera shell and real project, workspace, tab, terminal, file, editor, Git, GitHub, AI and operational flows can be built directly in GPUI.
- The runtime remains authoritative. The client does not access the SQLite catalog directly and does not fork Alera's domain behavior.
- Wayland is runnable and the X11 feature set compiles independently.
- Continuous terminal CPU fell from 82.0% to 14.5% of one core on the same machine, and the exact 2.56 MB restore fell from 1,351.24 ms median to 25.10 ms.
- Destructive filesystem, Git, forge and runtime operations retain path validation or explicit confirmation.

## Main Risks

| Risk | Level | Evidence And Mitigation |
| --- | --- | --- |
| Terminal feature completeness | High | Core data path and performance pass, but selection, IME, mouse modes, hyperlinks, search and modern protocols remain. Evaluate `libghostty-vt` for the production terminal and build a conformance suite. |
| Product UX breadth | High | Broad runtime domains are operational but several use JSON consoles. Replace them with typed GPUI screens incrementally. |
| GPUI ecosystem maturity | Medium | GPUI is fast and viable, but its ecosystem and API stability are smaller than Flutter's. Pin versions, isolate framework adapters and upgrade deliberately. |
| Linux platform details | Medium | Wayland ran and X11 compiled, but compositor, clipboard, IME, scaling and accessibility matrices still need real-device testing. |
| macOS and Windows | High | Explicitly outside this POC. Validate packaging, text input, window behavior and process integration before committing to cross-platform replacement. |
| Provider parity | Medium | GitHub is interactive; GitLab and Azure remain unimplemented. Keep forge logic behind a provider interface. |
| Licensing | Deferred | The user explicitly deferred licensing for the POC. A production plan must audit GPUI, gpui-component, Zed-derived ideas, terminal engines and every transitive dependency before distribution. |

## Recommended Next Phase

1. Harden the terminal first: selection/copy, IME, mouse/focus modes, hyperlink/search, process exit/restart, resize storms and byte-for-byte reconnect tests.
2. Decide Alacritty versus `libghostty-vt` with correctness fixtures in addition to the existing speed bakeoff.
3. Implement real split-pane layout and tab lifecycle against the existing runtime layout records.
4. Replace JSON consoles with typed screens for agents, resources, orchestration, settings, devices and diagnostics.
5. Add accessibility, command registry, menus, clipboard and keyboard-policy parity.
6. Package an opt-in Linux preview and run it beside Flutter on real repositories before scheduling any replacement.

## Decision Boundary

The POC is complete as a feasibility experiment. A release migration is not complete. Proceed only if the next phase is funded as a product implementation rather than treated as a mechanical UI rewrite.
