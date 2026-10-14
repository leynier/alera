use serde_json::json;

use crate::terminal_host::server::agent_chat_runtime::commands::{ChatOp, ConfigureInput};

use super::operation_wire::{decode_operation, encode_operation};
use super::queries::runtime_receipt_key;

#[test]
fn remote_operation_round_trip_preserves_model_effort_omission_selection_and_reset() {
    for value in [None, Some(None), Some(Some("high".to_owned()))] {
        for bound in [false, true] {
            let configure = ChatOp::Configure(ConfigureInput {
                model: value.clone(),
                reasoning_effort: value.clone(),
                ..Default::default()
            });
            let operation = if bound {
                ChatOp::WithinCeiling {
                    runtime_mode_ceiling: "approval-required".into(),
                    operation: Box::new(configure),
                }
            } else {
                configure
            };
            let wire = encode_operation(&operation);
            let decoded = decode_operation(&json!({"op":wire})).unwrap();
            let configure = if let ChatOp::WithinCeiling {
                runtime_mode_ceiling,
                operation,
            } = decoded
            {
                assert_eq!(runtime_mode_ceiling, "approval-required");
                *operation
            } else {
                decoded
            };
            let ChatOp::Configure(input) = configure else {
                panic!("expected configure");
            };
            assert_eq!(input.model, value);
            assert_eq!(input.reasoning_effort, value);
        }
    }
}

#[test]
fn operation_receipts_distinguish_omission_from_explicit_resets_inside_a_ceiling() {
    for bound in [false, true] {
        let receipt = |model, reasoning_effort| {
            let configure = ChatOp::Configure(ConfigureInput {
                model,
                reasoning_effort,
                ..Default::default()
            });
            let operation = if bound {
                ChatOp::WithinCeiling {
                    runtime_mode_ceiling: "approval-required".into(),
                    operation: Box::new(configure),
                }
            } else {
                configure
            };
            runtime_receipt_key("chat:parent", "configure", "once", "child", &operation)
        };
        let omit = receipt(None, None);
        let model_reset = receipt(Some(None), None);
        let effort_reset = receipt(None, Some(None));
        assert_eq!(omit.request_id, model_reset.request_id);
        assert_eq!(omit.request_id, effort_reset.request_id);
        assert_ne!(omit.digest, model_reset.digest);
        assert_ne!(omit.digest, effort_reset.digest);
        assert_ne!(model_reset.digest, effort_reset.digest);
    }
}
