use tokio::task::{JoinError, JoinHandle};

/// Aborts a spawned capture task if its owning command future is cancelled.
pub(crate) struct AbortOnDrop<T> {
    handle: Option<JoinHandle<T>>,
}

impl<T> AbortOnDrop<T> {
    pub(crate) fn new(handle: JoinHandle<T>) -> Self {
        Self {
            handle: Some(handle),
        }
    }

    pub(crate) fn as_mut(&mut self) -> Option<&mut JoinHandle<T>> {
        self.handle.as_mut()
    }

    pub(crate) fn take(&mut self) -> Option<JoinHandle<T>> {
        self.handle.take()
    }

    /// Awaits the owned task without detaching it if this future is cancelled.
    /// The handle is removed only after the join has completed.
    pub(crate) async fn join(&mut self) -> Result<T, JoinError> {
        let result = self.handle.as_mut().expect("owned task is present").await;
        let _ = self.handle.take();
        result
    }

    pub(crate) fn abort(&mut self) {
        if let Some(handle) = self.handle.as_ref() {
            handle.abort();
        }
    }

    pub(crate) async fn abort_and_join(&mut self) {
        if let Some(handle) = self.handle.take() {
            handle.abort();
            let _ = handle.await;
        }
    }
}

impl<T> Drop for AbortOnDrop<T> {
    fn drop(&mut self) {
        self.abort();
    }
}
