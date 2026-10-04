use super::*;

#[test]
fn exited_session_rejects_input_instead_of_leaving_request_pending() {
    let mut session = test_session();
    session.running = false;
    let error = session
        .queue_write(
            PtyWriteCompletion::ClientRequest {
                client_id: 1,
                request_id: 10,
            },
            b"input",
        )
        .expect_err("exited session should reject input");
    assert!(error.wire_message().contains("not running"));
}
