use super::ClientFrame;
#[cfg(test)]
use super::{UnboundedReceiver, CLIENT_TERMINAL_OUT_QUEUE_CAPACITY};
use crate::terminal_host::client_budget;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};
use tokio::sync::mpsc::{Sender, UnboundedSender};
/// The server's view of a connected client. Control traffic stays independent
/// from bounded terminal output so a terminal burst cannot drop RPC responses.
#[derive(Clone)]
pub struct ClientHandle {
    control_out: UnboundedSender<ClientFrame>,
    terminal_out: Sender<ClientFrame>,
    terminal_sequence: Arc<AtomicU64>,
    budget: Option<client_budget::ClientBudget>,
}

impl ClientHandle {
    pub fn new(
        control_out: UnboundedSender<ClientFrame>,
        terminal_out: Sender<ClientFrame>,
    ) -> Self {
        Self {
            control_out,
            terminal_out,
            terminal_sequence: Arc::new(AtomicU64::new(0)),
            budget: None,
        }
    }

    pub fn send_control(
        &self,
        frame: ClientFrame,
    ) -> Result<(), tokio::sync::mpsc::error::SendError<ClientFrame>> {
        let frame = if let Some(budget) = &self.budget {
            budget.reserve(frame).map_err(|frame| {
                budget.disconnect();
                tokio::sync::mpsc::error::SendError(frame)
            })?
        } else {
            frame
        };
        let terminal_watermark = self.terminal_sequence.load(Ordering::SeqCst);
        self.control_out.send(ClientFrame::OrderedControl {
            terminal_watermark,
            frame: Box::new(frame),
        })
    }

    pub fn try_send_terminal(
        &self,
        frame: ClientFrame,
    ) -> Result<(), tokio::sync::mpsc::error::TrySendError<ClientFrame>> {
        let frame = if let Some(budget) = &self.budget {
            budget
                .reserve(frame)
                .map_err(tokio::sync::mpsc::error::TrySendError::Full)?
        } else {
            frame
        };
        let sequence = self.terminal_sequence.fetch_add(1, Ordering::SeqCst) + 1;
        self.terminal_out.try_send(ClientFrame::SequencedTerminal {
            sequence,
            frame: Box::new(frame),
        })
    }

    pub(crate) fn with_budget(mut self, budget: client_budget::ClientBudget) -> Self {
        self.budget = Some(budget);
        self
    }
}

#[cfg(test)]
impl ClientHandle {
    pub fn test_channels() -> (Self, UnboundedReceiver<ClientFrame>) {
        let (control_out, control_out_rx) = tokio::sync::mpsc::unbounded_channel();
        let (terminal_out, _terminal_out_rx) =
            tokio::sync::mpsc::channel(CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
        (Self::new(control_out, terminal_out), control_out_rx)
    }

    /// Keeps the terminal lane receiver alive, so a test can read what was
    /// delivered and can fill the queue to reproduce backpressure. The plain
    /// [`Self::test_channels`] drops it, which makes every send read as closed.
    pub fn test_terminal_channels() -> (Self, tokio::sync::mpsc::Receiver<ClientFrame>) {
        let (control_out, _control_out_rx) = tokio::sync::mpsc::unbounded_channel();
        let (terminal_out, terminal_out_rx) =
            tokio::sync::mpsc::channel(CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
        (Self::new(control_out, terminal_out), terminal_out_rx)
    }
}
