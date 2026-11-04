use crate::{Generation, OpenCodeClient, OpenCodeError, OpenCodeModel};
use alera_agent_http::HttpTransport;
use serde_json::Value;

impl<T: HttpTransport> OpenCodeClient<T> {
    pub async fn list_models(&mut self) -> Result<Vec<OpenCodeModel>, OpenCodeError> {
        let path = if self.config().generation == Generation::V2 {
            "/model"
        } else {
            "/provider"
        };
        let response = self.raw_request("GET", path, None).await?;
        if self.config().generation == Generation::V2 {
            return response
                .body
                .get("data")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default()
                .into_iter()
                .map(|model| {
                    let provider_id = model
                        .get("providerID")
                        .and_then(Value::as_str)
                        .ok_or_else(|| OpenCodeError::protocol("OpenCode model has no providerID"))?
                        .to_owned();
                    let model_id = model
                        .get("modelID")
                        .or_else(|| model.get("id"))
                        .and_then(Value::as_str)
                        .ok_or_else(|| OpenCodeError::protocol("OpenCode model has no modelID"))?
                        .to_owned();
                    Ok(OpenCodeModel {
                        provider_id,
                        model_id,
                        name: model.get("name").and_then(Value::as_str).map(str::to_owned),
                        raw: model,
                    })
                })
                .collect();
        }
        let providers = response
            .body
            .get("providers")
            .or_else(|| response.body.get("data"))
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let mut models = Vec::new();
        for provider in providers {
            let provider_id = provider
                .get("id")
                .or_else(|| provider.get("providerID"))
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            if let Some(entries) = provider
                .get("models")
                .or_else(|| provider.get("model"))
                .and_then(Value::as_object)
            {
                models.extend(entries.iter().map(|(model_id, model)| OpenCodeModel {
                    provider_id: provider_id.clone(),
                    model_id: model_id.clone(),
                    name: model.get("name").and_then(Value::as_str).map(str::to_owned),
                    raw: model.clone(),
                }));
            }
        }
        Ok(models)
    }
}
