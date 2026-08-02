use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::prompt_image_store::{
    PromptImageStore, MAX_PROMPT_IMAGE_CHUNK_BYTES, MAX_PROMPT_IMAGE_STORE_BYTES,
};
use super::requests::require_string_key;
use super::ServerActor;

const MAX_ENCODED_CHUNK_BYTES: usize = MAX_PROMPT_IMAGE_CHUNK_BYTES.div_ceil(3) * 4;

impl ServerActor {
    pub(super) fn start_mobile_prompt_image_upload(&self, payload: &Value) -> HostResult<Value> {
        let format = require_string_key(payload, "format")?;
        let declared_bytes = payload
            .get("sizeBytes")
            .and_then(Value::as_u64)
            .or_else(|| payload.get("length").and_then(Value::as_u64))
            .ok_or_else(|| HostError::state("Prompt image sizeBytes must be an integer."))?;
        let reservation = PromptImageStore::in_runtime_dir(&self.runtime_dir)
            .start(&format, declared_bytes)
            .map_err(prompt_image_error)?;
        Ok(json!({
            "uploadId": reservation.upload_id,
            "chunkBytes": reservation.chunk_bytes,
            "maxFileBytes": super::prompt_image_store::MAX_PROMPT_IMAGE_BYTES,
            "maxStoreBytes": MAX_PROMPT_IMAGE_STORE_BYTES,
        }))
    }

    pub(super) fn append_mobile_prompt_image_chunk(&self, payload: &Value) -> HostResult<Value> {
        let upload_id = require_string_key(payload, "uploadId")?;
        let offset = payload
            .get("offset")
            .and_then(Value::as_u64)
            .ok_or_else(|| HostError::state("Prompt image offset must be an integer."))?;
        let encoded = require_string_key(payload, "dataBase64")?;
        if encoded.len() > MAX_ENCODED_CHUNK_BYTES {
            return Err(HostError::state(format!(
                "Prompt image chunk exceeds the {MAX_PROMPT_IMAGE_CHUNK_BYTES}-byte decoded limit."
            )));
        }
        let bytes = STANDARD
            .decode(encoded.as_bytes())
            .map_err(|_| HostError::state("Prompt image chunk is not valid base64."))?;
        let next_offset = PromptImageStore::in_runtime_dir(&self.runtime_dir)
            .append_chunk(&upload_id, offset, &bytes)
            .map_err(prompt_image_error)?;
        Ok(json!({"nextOffset": next_offset}))
    }

    pub(super) fn complete_mobile_prompt_image_upload(&self, payload: &Value) -> HostResult<Value> {
        let upload_id = require_string_key(payload, "uploadId")?;
        let path = PromptImageStore::in_runtime_dir(&self.runtime_dir)
            .complete(&upload_id)
            .map_err(prompt_image_error)?;
        Ok(json!({"path": path}))
    }

    pub(super) fn cancel_mobile_prompt_image_upload(&self, payload: &Value) -> HostResult<Value> {
        let upload_id = require_string_key(payload, "uploadId")?;
        PromptImageStore::in_runtime_dir(&self.runtime_dir)
            .cancel(&upload_id)
            .map_err(prompt_image_error)?;
        Ok(json!({}))
    }
}

fn prompt_image_error(error: super::prompt_image_store::PromptImageStoreError) -> HostError {
    HostError::state(error.to_string())
}
