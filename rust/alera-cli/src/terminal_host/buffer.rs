use std::collections::VecDeque;

/// How far into a trimmed tail to look for a line break before giving up and
/// cutting at a code point boundary instead.
const LINE_ALIGN_SCAN_BYTES: usize = 4 * 1024;

fn is_utf8_continuation(byte: u8) -> bool {
    byte & 0b1100_0000 == 0b1000_0000
}

/// Bounded scrollback buffer retaining at most `max_bytes` of the most recent
/// PTY output, including drop-oldest trimming and the special case for a single
/// chunk larger than the cap.
pub struct ScrollbackBuffer {
    chunks: VecDeque<Vec<u8>>,
    length: usize,
    max_bytes: usize,
}

impl ScrollbackBuffer {
    pub fn new(max_bytes: usize, initial: &[u8]) -> Self {
        let mut buffer = ScrollbackBuffer {
            chunks: VecDeque::new(),
            length: 0,
            max_bytes,
        };
        if !initial.is_empty() {
            buffer.append(initial);
        }
        buffer
    }

    pub fn set_max_bytes(&mut self, value: usize) {
        self.max_bytes = value;
        self.trim_to_limit();
    }

    pub fn append(&mut self, data: &[u8]) {
        if data.is_empty() {
            return;
        }
        // A single write larger than the cap collapses the buffer to its tail.
        if data.len() >= self.max_bytes {
            self.chunks.clear();
            let tail = data[data.len() - self.max_bytes..].to_vec();
            self.length = tail.len();
            self.chunks.push_back(tail);
            return;
        }
        self.chunks.push_back(data.to_vec());
        self.length += data.len();
        self.trim_to_limit();
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut output = Vec::with_capacity(self.length);
        for chunk in &self.chunks {
            output.extend_from_slice(chunk);
        }
        output
    }

    /// The buffer from `start` on, without materialising what comes before.
    ///
    /// A resuming client usually missed a few kilobytes of a multi-megabyte
    /// buffer, so copying the whole thing to slice off the tail is the bulk of
    /// the cost of answering it.
    pub fn slice_from(&self, start: usize) -> Vec<u8> {
        if start >= self.length {
            return Vec::new();
        }
        let mut output = Vec::with_capacity(self.length - start);
        let mut skipped = 0;
        for chunk in &self.chunks {
            if skipped + chunk.len() <= start {
                skipped += chunk.len();
                continue;
            }
            let offset = start.saturating_sub(skipped);
            output.extend_from_slice(&chunk[offset..]);
            skipped += chunk.len();
        }
        output
    }

    /// The last `max_bytes`, started at a line boundary when one is close by.
    ///
    /// Replaying more than the emulator will keep costs a VT parse per byte for
    /// history it drops on the floor. Cutting at a newline rather than mid-line
    /// also keeps a half-finished escape sequence out of the first row, since
    /// escapes almost never span one.
    pub fn tail(&self, max_bytes: usize) -> Vec<u8> {
        if self.length <= max_bytes {
            return self.to_bytes();
        }
        let bytes = self.slice_from(self.length - max_bytes);
        let start = match bytes
            .iter()
            .take(LINE_ALIGN_SCAN_BYTES)
            .position(|b| *b == b'\n')
        {
            Some(newline) => newline + 1,
            // No line break within reach, so settle for a code point boundary.
            None => bytes
                .iter()
                .position(|byte| !is_utf8_continuation(*byte))
                .unwrap_or(bytes.len()),
        };
        bytes[start..].to_vec()
    }

    #[allow(dead_code)]
    pub fn len(&self) -> usize {
        self.length
    }

    #[allow(dead_code)]
    pub fn is_empty(&self) -> bool {
        self.length == 0
    }

    fn trim_to_limit(&mut self) {
        if self.length <= self.max_bytes {
            return;
        }
        let mut excess = self.length - self.max_bytes;
        while excess > 0 {
            let Some(first) = self.chunks.pop_front() else {
                break;
            };
            if first.len() <= excess {
                self.length -= first.len();
                excess -= first.len();
                continue;
            }
            let remaining = first[excess..].to_vec();
            self.length -= excess;
            self.chunks.push_front(remaining);
            excess = 0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn appends_under_limit() {
        let mut buffer = ScrollbackBuffer::new(100, &[]);
        buffer.append(b"hello ");
        buffer.append(b"world");
        assert_eq!(buffer.to_bytes(), b"hello world");
        assert_eq!(buffer.len(), 11);
    }

    #[test]
    fn drops_oldest_chunks_over_limit() {
        let mut buffer = ScrollbackBuffer::new(5, &[]);
        buffer.append(b"abc");
        buffer.append(b"de");
        buffer.append(b"fg");
        // Keeps the most recent 5 bytes ("cdefg").
        assert_eq!(buffer.to_bytes(), b"cdefg");
        assert_eq!(buffer.len(), 5);
    }

    #[test]
    fn trims_partial_leading_chunk() {
        let mut buffer = ScrollbackBuffer::new(4, &[]);
        buffer.append(b"abcd");
        buffer.append(b"ef");
        // "abcd" + "ef" -> trim 2 from the front of "abcd" -> "cdef".
        assert_eq!(buffer.to_bytes(), b"cdef");
        assert_eq!(buffer.len(), 4);
    }

    #[test]
    fn single_chunk_larger_than_cap_keeps_tail() {
        let mut buffer = ScrollbackBuffer::new(3, &[]);
        buffer.append(b"abcdefg");
        assert_eq!(buffer.to_bytes(), b"efg");
        assert_eq!(buffer.len(), 3);
    }

    #[test]
    fn shrinking_max_bytes_trims_immediately() {
        let mut buffer = ScrollbackBuffer::new(10, &[]);
        buffer.append(b"abcdefgh");
        buffer.set_max_bytes(3);
        assert_eq!(buffer.to_bytes(), b"fgh");
        assert_eq!(buffer.len(), 3);
    }

    #[test]
    fn seeds_from_initial_buffer() {
        let buffer = ScrollbackBuffer::new(4, b"abcdef");
        assert_eq!(buffer.to_bytes(), b"cdef");
    }

    #[test]
    fn tail_cuts_at_a_line_break_when_one_is_in_reach() {
        let mut buffer = ScrollbackBuffer::new(100, &[]);
        buffer.append(b"first line\nsecond line\nthird line");
        assert_eq!(buffer.tail(1000), b"first line\nsecond line\nthird line");
        assert_eq!(buffer.tail(20), b"third line");
    }

    #[test]
    fn tail_without_a_line_break_stops_at_a_code_point_boundary() {
        let mut buffer = ScrollbackBuffer::new(100, &[]);
        buffer.append("aéb".as_bytes());
        // Four bytes: a, then the two of é, then b. A two-byte tail would start
        // on é's continuation byte, so é is dropped whole rather than mangled.
        assert_eq!(buffer.tail(2), b"b");
        assert_eq!(buffer.tail(3), "éb".as_bytes());
    }

    #[test]
    fn slices_from_an_offset_across_chunks() {
        let mut buffer = ScrollbackBuffer::new(100, &[]);
        buffer.append(b"abc");
        buffer.append(b"de");
        buffer.append(b"fgh");
        assert_eq!(buffer.slice_from(0), b"abcdefgh");
        assert_eq!(buffer.slice_from(3), b"defgh");
        assert_eq!(buffer.slice_from(4), b"efgh");
        assert_eq!(buffer.slice_from(8), b"");
        assert_eq!(buffer.slice_from(99), b"");
    }
}
