# Agent Transport

`JsonLineProcess` exchanges bounded JSON-lines frames with an external provider process. Stdout and stderr drain independently, and stdin writes remain independent of stdout backpressure. The default frame limit is 4 MiB, and stdout queues at most 32 data frames with one additional slot reserved for a terminal error.

A full stdout queue waits for the consumer to make space within `ProcessConfig.shutdown_timeout`. This lets a healthy consumer receive bursts larger than the queue in order without dropping frames or growing the queue. A stalled consumer receives `TransportError::OutputQueueFull` after the deadline. The same timeout bounds stdin writes and provides the grace period for child shutdown.

Cancelled sends retain the encoded frame, accepted prefix and original deadline. An identical retry completes the pending frame once, while a different send finishes it before writing the next frame. Fatal failures close the transport before cleanup awaits. If the caller cancels receive during cleanup, the next receive resumes cleanup and returns the original typed error once. The child remains owned while awaiting exit, so cleanup can resume after cancellation without abandoning child reaping.

`TransportError::ProcessExited` carries the last 64 KiB of the child's stderr with credentials masked by `redact_secrets`: values of keys whose name ends in a credential word (`OPENAI_API_KEY=`, `client_secret:`, `X-Auth-Token:`, `Authorization: Basic`, but not `max_tokens=`), Bearer tokens, `sk-`, GitHub and Slack tokens, HTTP user info and URL passwords. Once older output was dropped, the partial first line is dropped too, because it may hold a value cut off from its key. The alera-cli diagnostics sink applies the same rules.

`ManagedProcess` separately supports line-oriented provider servers, and `MockTransport` supplies scripted frames for provider tests. Their queue behavior is separate from the JSON protocol guarantees above. `ManagedProcess` returns stderr lines unmasked, because a provider can read its startup handshake from them.

Run validation from `rust/` with the pinned toolchain:

```sh
cargo test --locked -p alera-agent-transport
cargo clippy --locked -p alera-agent-transport --all-targets -- -D warnings
```

Tests cover framing limits, stderr tail redaction, a waiting receiver processing 100 buffered frames, a stalled receiver's bounded deadline and reserved error slot, full-duplex writes, cancellation, typed failures and process cleanup. They use local fixtures without model requests or credentials.
