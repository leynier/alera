//! `account.status` and sign-in bookkeeping shared by the browser and device
//! sign-ins.

use serde_json::{json, Value};

use crate::terminal_host::host_error::HostResult;

use super::account_requests::account_error;
use super::ServerActor;

impl ServerActor {
    pub(super) async fn account_status(&self) -> HostResult<Value> {
        let account = self
            .account_push
            .service
            .local_account()
            .await
            .map_err(account_error)?;
        Ok(json!({
            "connected": account.is_some(),
            "account": account,
            "signInPending": self.account_push.sign_in_cancel.is_some(),
            "lastSignIn": self.account_push.last_sign_in,
        }))
    }

    pub(super) fn cancel_account_sign_in(&mut self) -> Value {
        let cancelled = self
            .account_push
            .sign_in_cancel
            .take()
            .is_some_and(|cancel| cancel.send(()).is_ok());
        if cancelled {
            // Recorded now: `signInPending` turns false here, before the
            // attempt itself reports back.
            self.account_push.last_sign_in =
                Some(json!({ "ok": false, "message": "The sign-in was cancelled." }));
        }
        json!({ "cancelled": cancelled })
    }

    /// Remembers how the latest sign-in attempt ended. An account already
    /// signed in says nothing about whether a new attempt succeeded, so the
    /// CLI reads this instead.
    pub(super) fn record_sign_in_outcome(&mut self, result: &HostResult<Value>) {
        self.account_push.last_sign_in = Some(match result {
            Ok(_) => json!({ "ok": true }),
            Err(error) => json!({ "ok": false, "message": error.wire_message() }),
        });
    }
}
