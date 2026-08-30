use anyhow::{bail, Result};
use serde_json::Value;

pub(crate) fn contract_fields(
    contract: Option<&str>,
    inputs: Option<&str>,
) -> Result<Option<(Value, Value)>> {
    match (contract, inputs) {
        (None, None) => Ok(None),
        (Some(contract), Some(inputs)) => {
            if contract.len() > 64 * 1024 || inputs.len() > 256 * 1024 {
                bail!("role contract or inputs exceed the size limit");
            }
            Ok(Some((
                serde_json::from_str(contract)?,
                serde_json::from_str(inputs)?,
            )))
        }
        _ => bail!("--role-contract and --contract-inputs must be provided together"),
    }
}

pub(crate) fn with_contract_fields(mut payload: Value, fields: Option<(Value, Value)>) -> Value {
    if let Some((contract, inputs)) = fields {
        payload["roleContract"] = contract;
        payload["contractInputs"] = inputs;
    }
    payload
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn role_contract_cli_rejects_missing_inputs_and_ambiguous_legacy_schema() {
        use crate::cli::Cli;
        use clap::Parser;
        let base = ["alera", "orchestration", "task-create", "--spec", "Fix"];
        for extra in [
            vec!["--role-contract", "{}"],
            vec!["--contract-inputs", "{}"],
            vec![
                "--role-contract",
                "{}",
                "--contract-inputs",
                "{}",
                "--result-schema",
                "{}",
            ],
        ] {
            assert!(Cli::try_parse_from(base.into_iter().chain(extra)).is_err());
        }
        Cli::try_parse_from(base.into_iter().chain([
            "--role-contract",
            "{}",
            "--contract-inputs",
            "{}",
        ]))
        .unwrap();
    }

    #[test]
    fn legacy_payload_does_not_gain_new_fields() {
        let original = json!({"spec": "legacy"});
        assert_eq!(
            with_contract_fields(original.clone(), contract_fields(None, None).unwrap()),
            original
        );
    }

    #[test]
    fn contract_payload_requires_both_bounded_json_arguments() {
        assert!(contract_fields(Some("{}"), None).is_err());
        assert!(contract_fields(None, Some("{}")).is_err());
        assert!(contract_fields(Some("{"), Some("{}")).is_err());
        assert!(contract_fields(Some("{}"), Some(&" ".repeat(256 * 1024 + 1))).is_err());
        let payload = with_contract_fields(
            json!({}),
            contract_fields(Some(r#"{"version":1}"#), Some("{}")).unwrap(),
        );
        assert_eq!(payload["roleContract"]["version"], 1);
        assert_eq!(payload["contractInputs"], json!({}));
    }
}
