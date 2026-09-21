//! `alera runtime-attach --stdio`: the satellite end of a hub host link.
//!
//! The hub runs this over `ssh`. It connects to the satellite runtime host on
//! this machine (starting it persistent when it is not running), performs the
//! `hello` with the local token so the hub never learns it, announces the
//! attachment on stdout, and then pipes newline-delimited protocol frames
//! between stdio and the runtime socket. It knows nothing about the verbs it
//! carries, so a newer hub and satellite can add verbs without touching it.

use anyhow::{anyhow, Result};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

pub(crate) const ATTACHED_EVENT: &str = "hostLink.attached";

#[derive(Debug, clap::Args)]
pub(crate) struct RuntimeAttachArgs {
    #[command(flatten)]
    pub runtime: crate::cli::RuntimeDirArgs,
    /// Pipe protocol frames over stdin and stdout.
    #[arg(long)]
    pub stdio: bool,
}

pub(crate) async fn run(args: RuntimeAttachArgs) -> Result<i32> {
    if !args.stdio {
        return Err(anyhow!("runtime-attach requires --stdio"));
    }
    let runtime_dir = crate::runtime_dir(&args.runtime);
    let mut client =
        crate::runtime_host_client::RuntimeHostRpcClient::connect_or_start_persistent(&runtime_dir)
            .await?;
    let status = client.request_value("status.get", &json!({})).await?;
    let (reader, writer, _) = client.into_terminal_transport();
    let mut stdout = tokio::io::stdout();
    write_line(&mut stdout, &attached_event(&runtime_dir, &status)).await?;
    pump(reader, writer, tokio::io::stdin(), stdout).await
}

pub(crate) fn attached_event(runtime_dir: &std::path::Path, status: &Value) -> Value {
    json!({
        "event": ATTACHED_EVENT,
        "payload": {
            "runtimeDir": runtime_dir.display().to_string(),
            "platform": std::env::consts::OS,
            "arch": std::env::consts::ARCH,
            "hostVersion": status.get("hostVersion").cloned().unwrap_or(Value::Null),
            "runtimeCapabilities": status.get("runtimeCapabilities").cloned().unwrap_or_else(|| json!([])),
        }
    })
}

/// Copies frames in both directions until either side closes. Exit code 0 on
/// a clean hub disconnect, 1 when the runtime closed first, so the hub can
/// tell "the link was dropped" from "the satellite went away".
pub(crate) async fn pump<R, W, I, O>(
    mut runtime_lines: tokio::io::Lines<R>,
    mut runtime_writer: W,
    input: I,
    mut output: O,
) -> Result<i32>
where
    R: tokio::io::AsyncBufRead + Unpin,
    W: tokio::io::AsyncWrite + Unpin,
    I: tokio::io::AsyncRead + Unpin,
    O: tokio::io::AsyncWrite + Unpin,
{
    let mut input_lines = BufReader::new(input).lines();
    loop {
        tokio::select! {
            line = input_lines.next_line() => {
                match line? {
                    Some(line) => {
                        if line.trim().is_empty() {
                            continue;
                        }
                        runtime_writer.write_all(line.as_bytes()).await?;
                        runtime_writer.write_all(b"\n").await?;
                        runtime_writer.flush().await?;
                    }
                    None => return Ok(0),
                }
            }
            line = runtime_lines.next_line() => {
                match line? {
                    Some(line) => {
                        output.write_all(line.as_bytes()).await?;
                        output.write_all(b"\n").await?;
                        output.flush().await?;
                    }
                    None => return Ok(1),
                }
            }
        }
    }
}

async fn write_line(
    output: &mut (impl tokio::io::AsyncWrite + Unpin),
    value: &Value,
) -> Result<()> {
    let mut bytes = serde_json::to_vec(value)?;
    bytes.push(b'\n');
    output.write_all(&bytes).await?;
    output.flush().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn attached_event_carries_capabilities_and_platform() {
        let status = json!({
            "hostVersion": "1.2.3",
            "runtimeCapabilities": ["runtimeStore", "remoteSatelliteV1"],
        });
        let event = attached_event(std::path::Path::new("/tmp/data"), &status);
        assert_eq!(event["event"], ATTACHED_EVENT);
        assert_eq!(event["payload"]["runtimeDir"], "/tmp/data");
        assert_eq!(event["payload"]["hostVersion"], "1.2.3");
        assert_eq!(event["payload"]["platform"], std::env::consts::OS);
        assert!(event["payload"]["runtimeCapabilities"]
            .as_array()
            .unwrap()
            .iter()
            .any(|value| value == "remoteSatelliteV1"));
    }

    #[tokio::test]
    async fn pump_forwards_frames_both_ways_and_reports_which_side_closed() {
        let (hub_in, mut hub_write) = tokio::io::duplex(1024);
        let (runtime_read, mut runtime_side) = tokio::io::duplex(1024);
        let (mut hub_read, hub_out) = tokio::io::duplex(1024);
        let (runtime_in, runtime_writer) = tokio::io::duplex(1024);
        let pump = tokio::spawn(pump(
            BufReader::new(runtime_read).lines(),
            runtime_writer,
            hub_in,
            hub_out,
        ));
        hub_write
            .write_all(b"{\"id\":1,\"type\":\"status.get\"}\n")
            .await
            .unwrap();
        let mut runtime_lines = BufReader::new(runtime_in).lines();
        assert_eq!(
            runtime_lines.next_line().await.unwrap().unwrap(),
            "{\"id\":1,\"type\":\"status.get\"}"
        );
        runtime_side
            .write_all(b"{\"id\":1,\"ok\":true}\n")
            .await
            .unwrap();
        let mut hub_lines = BufReader::new(&mut hub_read).lines();
        assert_eq!(
            hub_lines.next_line().await.unwrap().unwrap(),
            "{\"id\":1,\"ok\":true}"
        );
        drop(hub_write);
        assert_eq!(pump.await.unwrap().unwrap(), 0);
    }

    #[tokio::test]
    async fn pump_exits_nonzero_when_the_runtime_closes_first() {
        let (hub_in, _hub_write) = tokio::io::duplex(64);
        let (runtime_read, runtime_side) = tokio::io::duplex(64);
        let (_hub_read, hub_out) = tokio::io::duplex(64);
        let (_runtime_in, runtime_writer) = tokio::io::duplex(64);
        drop(runtime_side);
        let code = pump(
            BufReader::new(runtime_read).lines(),
            runtime_writer,
            hub_in,
            hub_out,
        )
        .await
        .unwrap();
        assert_eq!(code, 1);
    }
}
