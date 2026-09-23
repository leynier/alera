# Workflow Lifecycle Visual Evidence

These captures use Alera's dark theme and bundled fonts. They document layout, not live-provider execution or production user data.

- `board-linux-overview.png`: native Linux Board navigation test at 1100 x 800, using `BoardTestRepository`.
- `controls-desktop.png`: execution controls and stage gate availability at 760 x 900.
- `controls-compact-cancel.png`: explicit cancellation confirmation at 420 x 900 and 200% text scale; the rest of the page remains scrollable.
- `controls-desktop-integration-recovery.png`: cancelled-run Attention with retained dirty integration work and explicit retry at 760 x 900.
- `controls-compact-integration-recovery-cancel.png`: non-mutating integration recovery confirmation at 420 x 900 and 200% text scale, scrolled to the confirmation.
- `cleanup-attention-desktop.png`: explicit retry and non-destructive abandonment at 760 x 900.
- `cleanup-attention-compact-footer.png`: recovery actions at 420 x 900 and 200% text scale, scrolled to the footer.
- `cleanup-abandoned-desktop.png`: durable abandonment receipt with remaining resources retained and no cleanup action.
- `new-run-desktop.png` and `new-run-form-desktop.png`: source, recipe, objective, selected profile and explicit proposal action at 800 x 600; the second capture is scrolled to the form footer.
- `plan-review-desktop.png`: frozen plan review with human approval and change-request actions at 800 x 600.
- `foundation-gate-desktop.png` and `foundation-gate-evidence.png`: integration SHA, task evidence and explicit gate approval at 800 x 600; the second capture is scrolled to the evidence/actions.
- `correction-desktop.png` and `correction-compact.png`: retained profile/revision context and corrective proposal, at 800 x 600 and 420 x 900 with 200% text respectively.
- `proposal-cancellation-attention.png`: explicit recovery of a cancelled coordinator without restarting it, at 800 x 600.

Reproduce the Board capture with `ALERA_FLAVOR=dev ALERA_VISUAL_REVIEW_DIR=<output> xvfb-run -a flutter test integration_test/run_board_flow_test.dart -d linux`. Reproduce the controls captures with `ALERA_WORKFLOW_VISUAL_DIR=<output> flutter test test/widget/workflow_controls_visual_test.dart`.

Reproduce cleanup captures with `ALERA_WORKFLOW_VISUAL_DIR=<output> flutter test test/widget/workflow_cleanup_visual_test.dart`. These are deterministic widget fixtures, not evidence that production resources were removed.

Reproduce proposal, review, gate and correction captures with `ALERA_WORKFLOW_VISUAL_DIR=<output> flutter test test/widget/workflow_proposals_test.dart test/widget/workflow_review_panel_test.dart test/widget/workflow_correction_page_test.dart`. These tests use fixture repositories, load the bundled Inter, JetBrains Mono, Material and Lucide fonts, and assert the associated interactions. Compact pages remain scrollable; captures show the documented viewport rather than a flattened full page.
