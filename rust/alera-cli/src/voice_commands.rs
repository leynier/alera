use anyhow::{Context, Result};
use serde_json::{json, Value};

use crate::cli::{VoiceAction, VoiceCommand};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::voice_capabilities::RUNTIME_HOST_VOICE_HOME_AGENT_CAPABILITY;

pub(crate) async fn run(command: VoiceCommand) -> i32 {
    match run_command(command).await {
        Ok(()) => 0,
        Err(error) => crate::print_error(error),
    }
}

async fn run_command(command: VoiceCommand) -> Result<()> {
    let json_output = command.output.json;
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(&command.runtime),
        RUNTIME_HOST_VOICE_HOME_AGENT_CAPABILITY,
    )
    .await?;
    let payload = match command.action {
        VoiceAction::Ensure => client.request_value("voice.ensure", &json!({})).await?,
        VoiceAction::Status => client.request_value("voice.status", &json!({})).await?,
        VoiceAction::Speak(args) => {
            let text = args.text.trim();
            if text.is_empty() {
                anyhow::bail!("--text cannot be empty");
            }
            client
                .request_value("voice.speak", &json!({ "text": text }))
                .await?
        }
    };
    print_payload(&payload, json_output)
}

fn print_payload(payload: &Value, json_output: bool) -> Result<()> {
    if json_output {
        println!(
            "{}",
            serde_json::to_string_pretty(payload).context("Could not encode JSON")?
        );
        return Ok(());
    }
    if let Some(message) = payload.get("message").and_then(Value::as_str) {
        println!("{message}");
        return Ok(());
    }
    println!(
        "{}",
        serde_json::to_string_pretty(payload).context("Could not encode JSON")?
    );
    Ok(())
}
