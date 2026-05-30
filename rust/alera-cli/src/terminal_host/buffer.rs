use std::collections::VecDeque;

/// Bounded scrollback buffer retaining at most `max_bytes` of the most recent
/// PTY output. Direct port of the Dart `_TerminalHostByteBuffer`, including its
/// drop-oldest trimming and the special case for a single chunk larger than the
/// cap.
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
}
