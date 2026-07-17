use std::io::{Read, Write};
use std::sync::mpsc::Receiver;
use std::sync::Arc;

use super::{PtyEvent, PtyWrite};

const READ_CHUNK_BYTES: usize = 64 * 1024;

/// Read the PTY on a dedicated thread, forwarding output and the final exit code.
pub(super) fn spawn_reader(
    mut reader: Box<dyn Read + Send>,
    mut child: Box<dyn portable_pty::Child + Send + Sync>,
    on_event: Arc<dyn Fn(PtyEvent) + Send + Sync>,
) {
    std::thread::Builder::new()
        .name("alera-pty-reader".to_string())
        .spawn(move || {
            let mut buffer = vec![0u8; READ_CHUNK_BYTES];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(read) => on_event(PtyEvent::Output(buffer[..read].to_vec())),
                    Err(error) => {
                        let code = child
                            .try_wait()
                            .ok()
                            .flatten()
                            .map(|status| status.exit_code() as i32)
                            .unwrap_or(-1);
                        on_event(PtyEvent::Error(error.to_string()));
                        on_event(PtyEvent::Exit(code));
                        return;
                    }
                }
            }
            let code = child
                .wait()
                .map(|status| status.exit_code() as i32)
                .unwrap_or(-1);
            on_event(PtyEvent::Exit(code));
        })
        .expect("failed to spawn pty reader thread");
}

pub(super) fn spawn_writer(
    mut writer: Box<dyn Write + Send>,
    input_rx: Receiver<PtyWrite>,
    on_event: Arc<dyn Fn(PtyEvent) + Send + Sync>,
) {
    std::thread::Builder::new()
        .name("alera-pty-writer".to_string())
        .spawn(move || {
            let mut writer_failure: Option<String> = None;
            while let Ok(request) = input_rx.recv() {
                let error = match writer_failure.as_ref() {
                    Some(message) => Some(message.clone()),
                    None => writer
                        .write_all(&request.bytes)
                        .and_then(|_| writer.flush())
                        .err()
                        .map(|error| error.to_string()),
                };
                if writer_failure.is_none() {
                    writer_failure.clone_from(&error);
                }
                on_event(PtyEvent::InputWritten {
                    completion: request.completion,
                    error,
                });
            }
        })
        .expect("failed to spawn PTY writer thread");
}
