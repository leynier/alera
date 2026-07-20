const MAX_TITLE_BYTES: usize = 4096;
const MAX_OSC_CODE_BYTES: usize = 16;

#[derive(Default)]
pub(super) struct TerminalTitleTracker {
    state: ParserState,
    code: Vec<u8>,
    title: Vec<u8>,
    title_valid: bool,
    current_title: Option<String>,
}

#[derive(Default)]
enum ParserState {
    #[default]
    Ground,
    Escape,
    OscCode,
    OscTitle,
    OscTitleTail,
    OscDiscard,
    OscEscape,
}

impl TerminalTitleTracker {
    pub(super) fn current_title(&self) -> Option<&str> {
        self.current_title.as_deref()
    }

    pub(super) fn feed(&mut self, data: &[u8]) -> Option<String> {
        let previous = self.current_title.clone();
        for &byte in data {
            self.feed_byte(byte);
        }
        (self.current_title != previous)
            .then(|| self.current_title.clone())
            .flatten()
    }

    fn feed_byte(&mut self, byte: u8) {
        match self.state {
            ParserState::Ground => {
                if byte == 0x1b {
                    self.state = ParserState::Escape;
                }
            }
            ParserState::Escape => {
                if byte == b']' {
                    self.code.clear();
                    self.title.clear();
                    self.title_valid = false;
                    self.state = ParserState::OscCode;
                } else if byte != 0x1b {
                    self.state = ParserState::Ground;
                }
            }
            ParserState::OscCode => match byte {
                0x07 => self.finish_osc(),
                0x1b => self.state = ParserState::OscEscape,
                b';' => {
                    self.title_valid = self.code == b"0" || self.code == b"2";
                    self.state = if self.title_valid {
                        ParserState::OscTitle
                    } else {
                        ParserState::OscDiscard
                    };
                }
                _ if self.code.len() < MAX_OSC_CODE_BYTES => self.code.push(byte),
                _ => {
                    self.title_valid = false;
                    self.state = ParserState::OscDiscard;
                }
            },
            ParserState::OscTitle => match byte {
                0x07 => self.finish_osc(),
                0x1b => self.state = ParserState::OscEscape,
                b';' => self.state = ParserState::OscTitleTail,
                _ if self.title.len() < MAX_TITLE_BYTES => self.title.push(byte),
                _ => {
                    self.title_valid = false;
                    self.state = ParserState::OscDiscard;
                }
            },
            ParserState::OscTitleTail => match byte {
                0x07 => self.finish_osc(),
                0x1b => self.state = ParserState::OscEscape,
                _ => {}
            },
            ParserState::OscDiscard => match byte {
                0x07 => self.reset_osc(),
                0x1b => self.state = ParserState::OscEscape,
                _ => {}
            },
            ParserState::OscEscape => {
                if byte == b'\\' {
                    self.finish_osc();
                } else {
                    self.reset_osc();
                }
            }
        }
    }

    fn finish_osc(&mut self) {
        if self.title_valid && self.title.len() <= MAX_TITLE_BYTES {
            self.current_title = Some(String::from_utf8_lossy(&self.title).into_owned());
        }
        self.reset_osc();
    }

    fn reset_osc(&mut self) {
        self.code.clear();
        self.title.clear();
        self.title_valid = false;
        self.state = ParserState::Ground;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tracks_osc_zero_and_two_with_both_terminators() {
        let mut tracker = TerminalTitleTracker::default();

        assert_eq!(tracker.feed(b"\x1b]0;Build\x07"), Some("Build".into()));
        assert_eq!(tracker.current_title(), Some("Build"));
        assert_eq!(tracker.feed(b"\x1b]2;Plan\x1b\\"), Some("Plan".into()));
        assert_eq!(tracker.current_title(), Some("Plan"));
    }

    #[test]
    fn tracks_sequences_split_across_output_chunks() {
        let mut tracker = TerminalTitleTracker::default();

        assert_eq!(tracker.feed(b"before\x1b]2;Review"), None);
        assert_eq!(tracker.feed(b" Tests\x1b"), None);
        assert_eq!(tracker.feed(b"\\after"), Some("Review Tests".into()));
    }

    #[test]
    fn reports_only_the_final_change_from_one_chunk() {
        let mut tracker = TerminalTitleTracker::default();

        assert_eq!(
            tracker.feed(b"\x1b]0;First\x07\x1b]2;Second\x07"),
            Some("Second".into()),
        );
        assert_eq!(tracker.feed(b"\x1b]2;Second\x07"), None);
    }

    #[test]
    fn matches_xterm_title_parameter_handling() {
        let mut tracker = TerminalTitleTracker::default();

        assert_eq!(
            tracker.feed(b"\x1b]2;First;Ignored\x07"),
            Some("First".into()),
        );
    }

    #[test]
    fn empty_title_clears_and_non_title_osc_is_ignored() {
        let mut tracker = TerminalTitleTracker::default();

        tracker.feed(b"\x1b]2;Active\x07");
        assert_eq!(tracker.feed(b"\x1b]1;Icon\x07"), None);
        assert_eq!(tracker.current_title(), Some("Active"));
        assert_eq!(tracker.feed(b"\x1b]2;\x07"), Some(String::new()));
        assert_eq!(tracker.current_title(), Some(""));
    }

    #[test]
    fn oversized_title_is_discarded() {
        let mut tracker = TerminalTitleTracker::default();
        tracker.feed(b"\x1b]2;Stable\x07");
        let mut sequence = b"\x1b]2;".to_vec();
        sequence.extend(std::iter::repeat_n(b'x', MAX_TITLE_BYTES + 1));
        sequence.push(0x07);

        assert_eq!(tracker.feed(&sequence), None);
        assert_eq!(tracker.current_title(), Some("Stable"));
    }
}
