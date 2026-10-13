//! The latched close signal of one host link.

use tokio::sync::watch;

/// Latched close signal shared by the writer, the reader and the link handle.
#[derive(Clone)]
pub(super) struct CloseSignal {
    sender: watch::Sender<bool>,
}

impl CloseSignal {
    pub(super) fn new() -> Self {
        Self {
            sender: watch::channel(false).0,
        }
    }

    pub(super) fn cancel(&self) {
        self.sender.send_replace(true);
    }

    pub(super) fn is_cancelled(&self) -> bool {
        *self.sender.borrow()
    }

    pub(super) async fn cancelled(&self) {
        let mut receiver = self.sender.subscribe();
        while !*receiver.borrow_and_update() {
            if receiver.changed().await.is_err() {
                return;
            }
        }
    }
}
