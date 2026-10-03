//! Output events a regression request read while waiting for its reply.

use std::cell::RefCell;
use std::collections::VecDeque;
#[cfg(unix)]
use std::io::{BufRead, BufReader};
#[cfg(unix)]
use std::net::TcpStream;
#[cfg(unix)]
use std::time::{Duration, Instant};

#[cfg(unix)]
use base64::engine::general_purpose::STANDARD;
#[cfg(unix)]
use base64::Engine as _;
#[cfg(unix)]
use serde_json::json;
use serde_json::Value;

thread_local! {
    /// The host flushes the first output after a quiet stream at once, so it
    /// can land before a reply rather than after it; dropping it there made
    /// later `collect_output` calls miss bytes the session really wrote.
    /// Each test runs on its own thread, so the buffer is per test.
    static UNREAD: RefCell<VecDeque<Value>> = const { RefCell::new(VecDeque::new()) };
}

/// Keeps an output event read while a request waited for its response.
pub(super) fn stash(message: Value) {
    UNREAD.with(|unread| unread.borrow_mut().push_back(message));
}

#[cfg(unix)]
pub(super) fn collect_output(
    reader: &mut BufReader<TcpStream>,
    session_id: &str,
    duration: Duration,
) -> String {
    let deadline = Instant::now() + duration;
    let mut output = String::new();
    // Output read while a request waited comes first, in arrival order; other
    // sessions' output stays queued for their own collection.
    UNREAD.with(|unread| {
        unread.borrow_mut().retain(|message| {
            if message["payload"]["sessionId"] != json!(session_id) {
                return true;
            }
            let bytes = STANDARD
                .decode(message["payload"]["dataBase64"].as_str().unwrap())
                .unwrap();
            output.push_str(&String::from_utf8_lossy(&bytes));
            false
        });
    });
    reader
        .get_mut()
        .set_read_timeout(Some(Duration::from_millis(300)))
        .unwrap();
    while Instant::now() < deadline {
        let mut line = String::new();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                let message: Value = serde_json::from_str(line.trim_end()).unwrap();
                if message.get("event") == Some(&json!("output"))
                    && message["payload"]["sessionId"] == json!(session_id)
                {
                    let bytes = STANDARD
                        .decode(message["payload"]["dataBase64"].as_str().unwrap())
                        .unwrap();
                    output.push_str(&String::from_utf8_lossy(&bytes));
                }
            }
            Err(_) => {}
        }
    }
    reader
        .get_mut()
        .set_read_timeout(Some(Duration::from_secs(15)))
        .unwrap();
    output
}
