//! App ids for provider-native identifiers. A native id is only unique
//! within one provider generation, so the mapping is keyed by generation and
//! keeps the id's JSON type; the app id it maps to is unique per chat and
//! kind for the chat's whole life, which keeps older turns addressable after
//! a provider switch.

use anyhow::Result;
use chrono::Utc;
use serde_json::Value;
use sqlx::{Row, SqliteConnection};

use super::agent_chat_models::*;
use super::agent_chat_store::require_session_row_in;
use super::agent_chat_validation::{native_id_json, require_id};
use super::{format_timestamp, RuntimeStore};

fn conflict(chat_id: &str, detail: String) -> anyhow::Error {
    AgentChatStoreError::NativeIdConflict {
        chat_id: chat_id.to_string(),
        detail,
    }
    .into()
}

async fn app_id_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    generation: i64,
    kind: &str,
    native_json: &str,
) -> Result<Option<String>> {
    Ok(sqlx::query_scalar(
        "SELECT appId FROM agentChatNativeIds \
         WHERE chatId = ? AND generation = ? AND kind = ? AND nativeIdJson = ?",
    )
    .bind(chat_id)
    .bind(generation)
    .bind(kind)
    .bind(native_json)
    .fetch_optional(&mut *connection)
    .await?)
}

impl RuntimeStore {
    /// Returns the app id for a native id, minting a UUIDv4 (or adopting
    /// `app_id`) the first time. Only the chat's current generation may add
    /// mappings; earlier generations stay readable.
    pub async fn map_agent_chat_native_id(&self, input: &AgentChatNativeIdInput) -> Result<String> {
        require_id("kind", &input.kind)?;
        let native_json = native_id_json(&input.native_id)?;
        if let Some(app_id) = &input.app_id {
            require_id("appId", app_id)?;
        }
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let row = require_session_row_in(&mut tx, &input.chat_id).await?;
        if let Some(existing) = app_id_in(
            &mut tx,
            &input.chat_id,
            input.generation,
            &input.kind,
            &native_json,
        )
        .await?
        {
            tx.commit().await?;
            if input
                .app_id
                .as_ref()
                .is_some_and(|wanted| wanted != &existing)
            {
                return Err(conflict(
                    &input.chat_id,
                    format!("{} {native_json} already maps to {existing}", input.kind),
                ));
            }
            return Ok(existing);
        }
        if input.generation != row.generation {
            return Err(conflict(
                &input.chat_id,
                format!(
                    "generation {} is not the current generation {}",
                    input.generation, row.generation
                ),
            ));
        }
        let app_id = input
            .app_id
            .clone()
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
        let taken: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM agentChatNativeIds WHERE chatId = ? AND kind = ? AND appId = ?)",
        )
        .bind(&input.chat_id)
        .bind(&input.kind)
        .bind(&app_id)
        .fetch_one(&mut *tx)
        .await?;
        if taken {
            return Err(conflict(
                &input.chat_id,
                format!(
                    "{} app id {app_id} already names another native id",
                    input.kind
                ),
            ));
        }
        sqlx::query(
            "INSERT INTO agentChatNativeIds (chatId, generation, kind, nativeIdJson, appId, createdAt) \
             VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(&input.chat_id)
        .bind(input.generation)
        .bind(&input.kind)
        .bind(&native_json)
        .bind(&app_id)
        .bind(format_timestamp(Utc::now()))
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(app_id)
    }

    /// The app id already mapped to a native id, without minting one.
    pub async fn agent_chat_app_id(
        &self,
        chat_id: &str,
        generation: i64,
        kind: &str,
        native_id: &Value,
    ) -> Result<Option<String>> {
        let native_json = native_id_json(native_id)?;
        let mut connection = self.pool().acquire().await?;
        app_id_in(&mut connection, chat_id, generation, kind, &native_json).await
    }

    /// The native id behind an app id, with the generation it belongs to.
    pub async fn agent_chat_native_id(
        &self,
        chat_id: &str,
        kind: &str,
        app_id: &str,
    ) -> Result<Option<AgentChatNativeId>> {
        let row = sqlx::query(
            "SELECT generation, nativeIdJson FROM agentChatNativeIds \
             WHERE chatId = ? AND kind = ? AND appId = ?",
        )
        .bind(chat_id)
        .bind(kind)
        .bind(app_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(|row| {
            Ok(AgentChatNativeId {
                chat_id: chat_id.to_string(),
                generation: row.try_get("generation")?,
                kind: kind.to_string(),
                native_id: serde_json::from_str(row.try_get::<&str, _>("nativeIdJson")?)?,
                app_id: app_id.to_string(),
            })
        })
        .transpose()
    }

    /// Records the provider thread of the current generation. A stale
    /// generation (the chat switched provider meanwhile) is refused so a
    /// late answer from the old provider cannot claim the new session.
    pub async fn bind_agent_chat_native_thread(
        &self,
        chat_id: &str,
        generation: i64,
        native_thread_id: Option<&str>,
    ) -> Result<()> {
        if let Some(native) = native_thread_id {
            require_id("nativeThreadId", native)?;
        }
        let result = sqlx::query(
            "UPDATE agentChatSessions SET nativeThreadId = ?, updatedAt = ? \
             WHERE chatId = ? AND generation = ?",
        )
        .bind(native_thread_id)
        .bind(format_timestamp(Utc::now()))
        .bind(chat_id)
        .bind(generation)
        .execute(self.pool())
        .await?;
        if result.rows_affected() == 0 {
            let exists: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM agentChatSessions WHERE chatId = ?)",
            )
            .bind(chat_id)
            .fetch_one(self.pool())
            .await?;
            if !exists {
                anyhow::bail!(AgentChatStoreError::NotFound(chat_id.to_string()));
            }
            return Err(conflict(
                chat_id,
                format!("generation {generation} is no longer current"),
            ));
        }
        Ok(())
    }
}
