# Workflow Lifecycle Visual Evidence

These captures use Alera's dark theme and bundled fonts. They document layout, not live-provider execution or production user data.

- `board-linux-overview.png`: native Linux Board navigation test at 1100 x 800, using `BoardTestRepository`.
- `controls-desktop.png`: execution controls and stage gate availability at 760 x 900.
- `controls-compact-cancel.png`: explicit cancellation confirmation at 420 x 900 and 200% text scale; the rest of the page remains scrollable.
- `cleanup-attention-desktop.png`: explicit retry and non-destructive abandonment at 760 x 900.
- `cleanup-attention-compact-footer.png`: recovery actions at 420 x 900 and 200% text scale, scrolled to the footer.
- `cleanup-abandoned-desktop.png`: durable abandonment receipt with remaining resources retained and no cleanup action.

Reproduce the Board capture with `ALERA_FLAVOR=dev ALERA_VISUAL_REVIEW_DIR=<output> xvfb-run -a flutter test integration_test/run_board_flow_test.dart -d linux`. Reproduce the controls captures with `ALERA_WORKFLOW_VISUAL_DIR=<output> flutter test test/widget/workflow_controls_visual_test.dart`.

Reproduce cleanup captures with `ALERA_WORKFLOW_VISUAL_DIR=<output> flutter test test/widget/workflow_cleanup_visual_test.dart`. These are deterministic widget fixtures, not evidence that production resources were removed.
