use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};
use std::collections::HashSet;
use tokio::io::{AsyncBufRead, AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, Lines};

pub(crate) async fn bridge<R, W, I, O>(
    mut frames: Lines<R>,
    mut writer: W,
    mut input: I,
    mut output: O,
    attachment: Value,
    mut next_id: i64,
    dimensions: impl Fn() -> Option<(u16, u16)>,
) -> Result<i32>
where
    R: AsyncBufRead + Unpin,
    W: AsyncWrite + Unpin,
    I: AsyncRead + Unpin,
    O: AsyncWrite + Unpin,
{
    let session = attachment["sessionId"]
        .as_str()
        .ok_or_else(|| anyhow!("Session identity is required"))?
        .to_string();
    let attach_id = next_id;
    next_id += 1;
    let requested_size = (
        attachment["cols"].as_u64().unwrap_or(80) as u16,
        attachment["rows"].as_u64().unwrap_or(24) as u16,
    );
    let mut current_size = (0, 0);
    send(&mut writer, attach_id, "createOrAttach", attachment).await?;
    let mut attached = false;
    let mut pending_input = HashSet::new();
    let mut pending_resume = None;
    let mut bytes = [0u8; 4096];
    let deadline = tokio::time::sleep(std::time::Duration::from_secs(30));
    tokio::pin!(deadline);
    let mut resize_tick = tokio::time::interval(std::time::Duration::from_millis(200));
    loop {
        tokio::select! {
            _ = resize_tick.tick(), if attached && pending_input.len() < 16 => {
                if let Some(size) = dimensions().or(Some(requested_size)).filter(|size| *size != current_size && size.0 > 0 && size.1 > 0) {
                    let id = next_id;
                    next_id += 1;
                    pending_input.insert(id);
                    send(&mut writer, id, "resize", json!({"sessionId":session,"cols":size.0,"rows":size.1})).await?;
                    current_size = size;
                }
            }
            _ = &mut deadline, if !attached => bail!("The owner runtime did not confirm terminal attachment; remote process closure is unverified"),
            read = input.read(&mut bytes), if attached && pending_input.len() < 16 => {
                let count = read?;
                if count == 0 { bail!("Terminal input closed; the remote session remains owned by its runtime"); }
                let id = next_id;
                next_id += 1;
                pending_input.insert(id);
                send(&mut writer, id, "write", json!({"sessionId": session, "dataBase64": crate::terminal_host::protocol::encode_bytes(&bytes[..count])})).await?;
            }
            line = frames.next_line() => {
                let line = line?.ok_or_else(|| anyhow!("The owner connection closed; remote process closure is unverified"))?;
                let frame: Value = serde_json::from_str(&line)?;
                if pending_resume.is_some() && frame["id"].as_i64() == pending_resume {
                    pending_resume = None;
                    if frame["ok"] != true { bail!("Owner output resynchronization failed: {}", frame["error"].as_str().unwrap_or("unknown error")); }
                    let payload = &frame["payload"];
                    if payload["delta"] != true {
                        if payload["sessionId"].as_str() != Some(session.as_str()) { bail!("The owner returned another terminal identity during resynchronization"); }
                        // A replacement snapshot must not append duplicated history or
                        // inherit interaction modes from output lost under backpressure.
                        output.write_all(b"\x1bc").await?;
                        replay_snapshot(&mut output, payload, dimensions().unwrap_or(requested_size)).await?;
                        if let Some(size) = snapshot_dimensions(payload) { current_size = size; }
                    }
                    continue;
                }
                if frame["id"].as_i64() == Some(attach_id) || frame["id"].as_i64().is_some_and(|id| pending_input.remove(&id)) {
                    if frame["ok"] != true { bail!("Owner terminal request failed: {}", frame["error"].as_str().unwrap_or("unknown error")); }
                    if frame["id"].as_i64() == Some(attach_id) {
                        if frame["payload"]["sessionId"].as_str() != Some(session.as_str()) { bail!("The owner returned another terminal identity"); }
                        replay_snapshot(&mut output, &frame["payload"], dimensions().unwrap_or(requested_size)).await?;
                        current_size = (
                            frame["payload"]["snapshotCols"].as_u64().and_then(|value| u16::try_from(value).ok()).unwrap_or(0),
                            frame["payload"]["snapshotRows"].as_u64().and_then(|value| u16::try_from(value).ok()).unwrap_or(0),
                        );
                        attached = true;
                    }
                    continue;
                }
                if frame["payload"]["sessionId"].as_str() != Some(session.as_str()) { continue; }
                match frame["event"].as_str() {
                    Some("outputResyncRequired") if pending_resume.is_none() => {
                        let id = next_id;
                        next_id += 1;
                        pending_resume = Some(id);
                        send(&mut writer, id, "setOutputPaused", json!({"sessionId":session,"paused":false})).await?;
                    }
                    Some("output") => {
                        output.write_all(&crate::terminal_host::protocol::decode_bytes(frame["payload"].get("dataBase64"))?).await?;
                        output.flush().await?;
                    }
                    Some("exit") => return frame["payload"]["exitCode"].as_i64().and_then(|code| i32::try_from(code).ok()).ok_or_else(|| anyhow!("Invalid remote exit status")),
                    Some("error") => bail!("Remote terminal failed: {}", frame["payload"]["error"].as_str().unwrap_or("unknown error")),
                    Some("terminalSessionRemoved") => bail!("The owner removed this terminal session. Process closure must be verified by the workspace operation result."),
                    _ => {},
                }
            }
        }
    }
}

fn snapshot_dimensions(payload: &Value) -> Option<(u16, u16)> {
    let cols = u16::try_from(payload["snapshotCols"].as_u64()?).ok()?;
    let rows = u16::try_from(payload["snapshotRows"].as_u64()?).ok()?;
    (cols > 0 && rows > 0).then_some((cols, rows))
}

async fn replay_snapshot(
    output: &mut (impl AsyncWrite + Unpin),
    payload: &Value,
    viewport: (u16, u16),
) -> Result<()> {
    let snapshot = crate::terminal_host::protocol::decode_bytes(payload.get("snapshotBase64"))?;
    let geometry = snapshot_dimensions(payload)
        .filter(|size| *size != viewport && viewport.0 > 0 && viewport.1 > 0);
    if let Some((cols, rows)) = geometry {
        // Replaying absolute cursor moves at the current width corrupts the
        // screen before reflow. Alera's emulator supports character-size CSI.
        output
            .write_all(format!("\x1b[8;{rows};{cols}t").as_bytes())
            .await?;
    }
    output.write_all(&snapshot).await?;
    if geometry.is_some() {
        output
            .write_all(format!("\x1b[8;{};{}t", viewport.1, viewport.0).as_bytes())
            .await?;
    }
    output.flush().await?;
    Ok(())
}

async fn send(
    writer: &mut (impl AsyncWrite + Unpin),
    id: i64,
    verb: &str,
    payload: Value,
) -> Result<()> {
    let mut bytes = serde_json::to_vec(&json!({"id": id, "type": verb, "payload": payload}))?;
    bytes.push(b'\n');
    writer.write_all(&bytes).await?;
    writer.flush().await?;
    Ok(())
}

#[cfg(test)]
#[path = "remote_terminal_bridge_tests.rs"]
mod tests;
