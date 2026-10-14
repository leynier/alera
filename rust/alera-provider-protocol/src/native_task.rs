use crate::{error::nonempty, ProviderError, ProviderEvent};
use serde::{Deserialize, Serialize};

/// Provider-observed lineage. These references never allocate host chat/task ids.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeTask {
    pub native_task_id: Option<String>,
    pub parent_native_thread_id: Option<String>,
    pub child_native_thread_ids: Vec<String>,
    pub native_tool_call_id: Option<String>,
    pub status: Option<String>,
}

impl NativeTask {
    pub fn validate(&self) -> Result<(), ProviderError> {
        for (value, name) in [
            (&self.native_task_id, "nativeTaskId"),
            (&self.parent_native_thread_id, "parentNativeThreadId"),
            (&self.native_tool_call_id, "nativeToolCallId"),
        ] {
            if let Some(value) = value {
                nonempty(value, name)?;
            }
        }
        for id in &self.child_native_thread_ids {
            nonempty(id, "childNativeThreadId")?;
        }
        if self.native_task_id.is_none()
            && self.native_tool_call_id.is_none()
            && self.child_native_thread_ids.is_empty()
        {
            return Err(ProviderError::Validation(
                "native lineage requires a provider-observed reference".into(),
            ));
        }
        Ok(())
    }
}

impl ProviderEvent {
    pub fn native_task(&self) -> Result<Option<NativeTask>, ProviderError> {
        self.payload
            .get("nativeTask")
            .map(|value| {
                let task: NativeTask = serde_json::from_value(value.clone()).map_err(|error| {
                    ProviderError::Validation(format!("invalid nativeTask: {error}"))
                })?;
                task.validate()?;
                Ok(task)
            })
            .transpose()
    }
}
