use super::*;

#[test]
fn mobile_allowlist_excludes_managed_workspace_mutations() {
    assert!(!mobile_request_allowed("workspace.createManaged"));
    assert!(!mobile_request_allowed("workspace.removeManaged"));
}

#[test]
fn terminal_read_cursor_advances_across_trimmed_scrollback() {
    assert_eq!(terminal_read_window(0, 4, None, 4), (0, 0, 4));
    assert_eq!(terminal_read_window(2, 6, Some(4), 4), (4, 4, 6));
    assert_eq!(terminal_read_window(8, 12, Some(4), 4), (4, 8, 12));
}

#[test]
fn terminal_text_pages_do_not_split_valid_utf8_scalars() {
    let bytes = "aé🙂z".as_bytes();
    let mut cursor = 0;
    let mut text = String::new();
    while cursor < bytes.len() as u64 {
        let (_, start, next) = terminal_read_window(0, bytes.len() as u64, Some(cursor), 1);
        let (start, next) = align_terminal_text_window(bytes, 0, start, next);
        assert!(next > cursor);
        text.push_str(std::str::from_utf8(&bytes[start as usize..next as usize]).unwrap());
        cursor = next;
    }
    assert_eq!(text, "aé🙂z");
    assert!(!text.contains('\u{fffd}'));
}

#[test]
fn terminal_text_window_skips_an_explicit_cursor_inside_a_scalar() {
    let bytes = "aéz".as_bytes();
    assert_eq!(align_terminal_text_window(bytes, 0, 2, 3), (3, 3));
    assert_eq!(align_terminal_text_window(&[0x80, b'a'], 0, 0, 1), (0, 1));
}
