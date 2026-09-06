const CURSOR_QUERY: &[u8] = b"\x1b[6n";
#[cfg(windows)]
pub(super) const INITIAL_CURSOR: &[u8] = b"\x1b[1;1R";

#[derive(Default)]
pub(super) struct ConptyStartupOutput {
    prefix: Vec<u8>,
    settled: bool,
}

impl ConptyStartupOutput {
    pub(super) fn feed(&mut self, bytes: &[u8]) -> Vec<u8> {
        if self.settled {
            return bytes.to_vec();
        }
        let take = (CURSOR_QUERY.len() - self.prefix.len()).min(bytes.len());
        self.prefix.extend_from_slice(&bytes[..take]);
        if !CURSOR_QUERY.starts_with(&self.prefix) {
            self.settled = true;
            let mut output = std::mem::take(&mut self.prefix);
            output.extend_from_slice(&bytes[take..]);
            return output;
        }
        if self.prefix.len() == CURSOR_QUERY.len() {
            self.settled = true;
            self.prefix.clear();
            return bytes[take..].to_vec();
        }
        Vec::new()
    }

    pub(super) fn finish(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.prefix)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workflow_conpty_startup_consumes_only_the_initial_query_at_every_split() {
        for split in 0..=CURSOR_QUERY.len() {
            let mut filter = ConptyStartupOutput::default();
            assert!(filter.feed(&CURSOR_QUERY[..split]).is_empty());
            let mut rest = CURSOR_QUERY[split..].to_vec();
            rest.extend_from_slice(b"ready\x1b[6n");
            assert_eq!(filter.feed(&rest), b"ready\x1b[6n");
            assert_eq!(filter.feed(CURSOR_QUERY), CURSOR_QUERY);
            assert!(filter.finish().is_empty());
        }
    }

    #[test]
    fn workflow_conpty_startup_preserves_other_output_and_truncated_prefixes() {
        let mut filter = ConptyStartupOutput::default();
        assert!(filter.feed(b"\x1b[").is_empty());
        assert_eq!(filter.feed(b"?25hready"), b"\x1b[?25hready");
        let mut truncated = ConptyStartupOutput::default();
        assert!(truncated.feed(b"\x1b").is_empty());
        assert_eq!(truncated.finish(), b"\x1b");
    }
}
