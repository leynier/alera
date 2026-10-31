use super::StderrTail;
use crate::framing::STDERR_TAIL_BYTES;

#[test]
fn text_masks_credentials() {
    let mut tail = StderrTail::default();
    tail.append(b"starting\nOPENAI_API_KEY=sk-proj-abcdefghijklmnop\n");
    tail.append(b"Authorization: Bearer abc.def\nexiting\n");

    assert_eq!(
        tail.text(),
        "starting\nOPENAI_API_KEY=[redacted]\nAuthorization: Bearer [redacted]\nexiting\n"
    );
}

#[test]
fn untruncated_tail_keeps_its_first_line() {
    let mut tail = StderrTail::default();
    tail.append(b"first line\nsecond line");

    assert_eq!(tail.text(), "first line\nsecond line");
}

#[test]
fn truncated_tail_drops_the_partial_line_a_key_was_cut_from() {
    let mut tail = StderrTail::default();
    tail.append(b"MY_API_KEY=");
    tail.append(&vec![b'a'; STDERR_TAIL_BYTES - 16]);
    tail.append(b"\nprovider failed\n");

    let text = tail.text();
    assert_eq!(text, "provider failed\n");
}

#[test]
fn oversized_chunk_keeps_only_the_newest_bytes() {
    let mut tail = StderrTail::default();
    let mut chunk = vec![b'x'; STDERR_TAIL_BYTES];
    chunk.extend_from_slice(b"\nlast line");
    tail.append(&chunk);

    assert_eq!(tail.text(), "last line");
}

#[test]
fn truncated_single_line_is_kept() {
    let mut tail = StderrTail::default();
    tail.append(&vec![b'y'; STDERR_TAIL_BYTES + 8]);

    assert_eq!(tail.text().len(), STDERR_TAIL_BYTES);
}
