use super::*;
use crate::terminal_host::relay_crypto;
use tokio::sync::mpsc::{Receiver, UnboundedReceiver};

pub(super) async fn write_peer(
    numeric_id: u64,
    client_id: String,
    mut session: relay_crypto::RelaySession,
    inbox: UnboundedSender<ServerCommand>,
    outbound_tx: Sender<RelayOutbound>,
    mut control_rx: UnboundedReceiver<ClientFrame>,
    mut terminal_rx: Receiver<ClientFrame>,
) {
    let mut binary = false;
    let mut ordering = ClientFrameOrdering::default();
    loop {
        tokio::select! {
            control = control_rx.recv() => {
                let Some(control) = control else { break; };
                let mut output = PeerOutput {
                    numeric_id,
                    terminal_rx: &mut terminal_rx,
                    ordering: &mut ordering,
                    binary: &mut binary,
                    outbound_tx: &outbound_tx,
                    inbox: &inbox,
                };
                if send_control(&mut session, &client_id, control, &mut output)
                    .await
                    .is_err()
                {
                    break;
                }
            }
            terminal = terminal_rx.recv() => {
                let Some(terminal) = terminal else { break; };
                ordering.stage_terminal(terminal);
                let frame = ordering.take_pending_terminal().expect("staged terminal frame");
                if send_frame(numeric_id, &mut session, &client_id, frame, &mut binary, &outbound_tx, &inbox).await.is_err() { break; }
            }
        }
    }
    let _ = inbox.send(ServerCommand::ClientDisconnected { id: numeric_id });
}

struct PeerOutput<'a> {
    numeric_id: u64,
    terminal_rx: &'a mut Receiver<ClientFrame>,
    ordering: &'a mut ClientFrameOrdering,
    binary: &'a mut bool,
    outbound_tx: &'a Sender<RelayOutbound>,
    inbox: &'a UnboundedSender<ServerCommand>,
}

async fn send_control(
    session: &mut relay_crypto::RelaySession,
    client_id: &str,
    control: ClientFrame,
    output: &mut PeerOutput<'_>,
) -> anyhow::Result<()> {
    let (terminal, control) = output.ordering.before_control(control, output.terminal_rx);
    for frame in terminal {
        send_frame(
            output.numeric_id,
            session,
            client_id,
            frame,
            output.binary,
            output.outbound_tx,
            output.inbox,
        )
        .await?;
    }
    send_frame(
        output.numeric_id,
        session,
        client_id,
        control,
        output.binary,
        output.outbound_tx,
        output.inbox,
    )
    .await
}

async fn send_frame(
    numeric_id: u64,
    session: &mut relay_crypto::RelaySession,
    client_id: &str,
    frame: ClientFrame,
    binary: &mut bool,
    outbound_tx: &Sender<RelayOutbound>,
    inbox: &UnboundedSender<ServerCommand>,
) -> anyhow::Result<()> {
    if matches!(frame, ClientFrame::UpgradeToBinary) {
        *binary = true;
        return Ok(());
    }
    if let ClientFrame::RestartRuntimeAfterWrite { .. } = frame {
        let _ = inbox.send(ServerCommand::RequestedRestart);
        return Ok(());
    }
    let payload = if *binary {
        if let ClientFrame::Output { session_id, data } = &frame {
            encode_output_payload(session_id, data)
        } else {
            serde_json::to_vec(&frame.as_json().unwrap_or_default())?
        }
    } else {
        let Some(value) = frame.as_json() else {
            return Ok(());
        };
        serde_json::to_vec(&value)?
    };
    let payload = session
        .seal(&payload)
        .map_err(|error| anyhow::anyhow!(error))?;
    outbound_tx
        .send(RelayOutbound {
            numeric_id,
            client_id: client_id.to_owned(),
            payload,
        })
        .await
        .map_err(|_| anyhow::anyhow!("relay writer is closed"))
}
