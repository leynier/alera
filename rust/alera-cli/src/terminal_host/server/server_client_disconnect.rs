use super::{AdmissionClass, ServerCommand, ServerInbox, ServerInboxSendError};

/// Reserves cleanup before registration so aborting a relay peer cannot leak an
/// actor client, even when every remaining control slot is occupied.
pub(crate) struct ServerClientDisconnect {
    id: u64,
    inbox: ServerInbox,
}

const DISCONNECT_ADMISSION: AdmissionClass = AdmissionClass::Control { bytes: 1 };

impl Drop for ServerClientDisconnect {
    fn drop(&mut self) {
        if self
            .inbox
            .tx
            .send(ServerCommand::ClientDisconnected { id: self.id })
            .is_err()
        {
            self.inbox.admission.release(DISCONNECT_ADMISSION);
        }
    }
}

impl ServerInbox {
    pub(crate) async fn reserve_client_disconnect(
        &self,
        id: u64,
    ) -> Result<ServerClientDisconnect, ServerInboxSendError> {
        loop {
            let notified = self.admission.capacity_notified();
            let mut notified = std::pin::pin!(notified);
            notified.as_mut().enable();
            if let Some(reservation) = self.admission.try_acquire(DISCONNECT_ADMISSION, None) {
                drop(reservation);
                return Ok(ServerClientDisconnect {
                    id,
                    inbox: self.clone(),
                });
            }
            if self.admission.is_closed() {
                return Err(ServerInboxSendError::Closed);
            }
            notified.await;
        }
    }
}
