//! The run and recipe verbs a phone may send through the mobile gateway.

/// Every `runs.*` verb and the read-only recipe verbs. Recipe writes, every
/// `orchestration.*` verb, `host.process.run`, `inbox.wait` and the agent
/// conversation reads (`inbox.conversations`, `inbox.conversation`, replaced on
/// the phone by run timelines) stay local-only.
pub(in crate::terminal_host::server) const MOBILE_RUN_VERBS: &[&str] = &[
    "runs.board",
    "runs.snapshot",
    "runs.task",
    "runs.timeline",
    "runs.source",
    "runs.create",
    "runs.plan",
    "runs.gates",
    "runs.gate",
    "runs.resolveGate",
    "runs.control",
    "runs.retryTask",
    "runs.retryIntegration",
    "runs.retryCancellation",
    "runs.resources",
    "runs.cleanups",
    "runs.previewCleanup",
    "runs.cleanup",
    "runs.applyCleanup",
    "runs.retryCleanup",
    "runs.abandonCleanup",
    "runs.integrations",
    "runs.integration",
    "recipes.catalog",
    "recipes.recipe",
];
