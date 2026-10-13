use crate::frb_generated::StreamSink;
use alera_core::source_control as sc;

// JSON envelopes keep the progress capability additive without duplicating
// the shared GitError enum in another bridge model.
pub fn git_network_progress(path: String, push: bool, sink: StreamSink<String>) {
    let output = |line: String| {
        let _ = sink.add(serde_json::json!({ "line": line }).to_string());
    };
    let result = if push {
        sc::git_push_with_progress(path, &output)
    } else {
        sc::git_pull_with_progress(path, &output)
    };
    let terminal = match result {
        Ok(()) => serde_json::json!({ "done": true }),
        Err(error) => {
            serde_json::json!({ "done": true, "error": error.context, "errorKind": error.kind })
        }
    };
    let _ = sink.add(terminal.to_string());
}
