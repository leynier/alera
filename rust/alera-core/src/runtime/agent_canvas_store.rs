use anyhow::{anyhow, bail, Result};
use chrono::{Duration, Utc};
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use super::store::format_timestamp;
use super::{
    AgentCanvas, AgentCanvasDecision, AgentCanvasDecisionState, AgentCanvasEvent, AgentCanvasState,
    RuntimeStore, RuntimeStoreError, AGENT_CANVAS_COMPONENTS, AGENT_CANVAS_MAX_COMPONENTS,
    AGENT_CANVAS_MAX_DECISIONS, AGENT_CANVAS_MAX_DOCUMENT_BYTES, AGENT_CANVAS_MAX_EVENTS,
    AGENT_CANVAS_MAX_PER_WORKSPACE, AGENT_CANVAS_PROTOCOL_VERSION, AGENT_CANVAS_RETENTION_HOURS,
};

pub(super) const AGENT_CANVAS_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS agentCanvases (
        id TEXT PRIMARY KEY,
        workspaceId TEXT NOT NULL,
        terminalSessionId TEXT NOT NULL,
        tabId TEXT,
        agentType TEXT NOT NULL,
        title TEXT NOT NULL,
        state TEXT NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        frozen INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 0,
        finalRevision INTEGER,
        documentJson TEXT NOT NULL DEFAULT '{}',
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        completedAt TEXT,
        expiresAt TEXT
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS agentCanvasesIdentityIdx ON agentCanvases(workspaceId, terminalSessionId);",
    "CREATE INDEX IF NOT EXISTS agentCanvasesWorkspaceStateIdx ON agentCanvases(workspaceId, state, pinned, updatedAt DESC);",
    "CREATE TABLE IF NOT EXISTS agentCanvasRevisions (
        canvasId TEXT NOT NULL,
        revision INTEGER NOT NULL,
        documentJson TEXT NOT NULL,
        semanticHash TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        PRIMARY KEY(canvasId, revision)
    );",
    "CREATE INDEX IF NOT EXISTS agentCanvasRevisionsCanvasIdx ON agentCanvasRevisions(canvasId, revision DESC);",
    "CREATE TABLE IF NOT EXISTS agentCanvasDecisions (
        id TEXT PRIMARY KEY,
        canvasId TEXT NOT NULL,
        revision INTEGER NOT NULL,
        question TEXT NOT NULL,
        optionsJson TEXT NOT NULL DEFAULT '[]',
        state TEXT NOT NULL,
        resolutionJson TEXT,
        createdAt TEXT NOT NULL,
        resolvedAt TEXT,
        expiresAt TEXT
    );",
    "CREATE INDEX IF NOT EXISTS agentCanvasDecisionsCanvasIdx ON agentCanvasDecisions(canvasId, state, createdAt);",
    "CREATE TABLE IF NOT EXISTS agentCanvasEvents (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        canvasId TEXT NOT NULL,
        workspaceId TEXT NOT NULL,
        eventType TEXT NOT NULL,
        payloadJson TEXT NOT NULL DEFAULT '{}',
        createdAt TEXT NOT NULL
    );",
    "CREATE INDEX IF NOT EXISTS agentCanvasEventsWorkspaceIdx ON agentCanvasEvents(workspaceId, sequence);",
    "CREATE INDEX IF NOT EXISTS agentCanvasEventsCanvasIdx ON agentCanvasEvents(canvasId, sequence);",
];

const CANVAS_COLUMNS: &str = "id, workspaceId, terminalSessionId, tabId, agentType, title, state, pinned, frozen, revision, finalRevision, documentJson, createdAt, updatedAt, completedAt, expiresAt";

include!("agent_canvas_store_catalog.rs");
include!("agent_canvas_store_mutations.rs");
include!("agent_canvas_store_decisions.rs");
include!("agent_canvas_store_support.rs");
