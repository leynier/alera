use crate::OpenCodeError;

pub const DEFAULT_MAX_SSE_EVENT_BYTES: usize = 4 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SseFrame {
    pub event: Option<String>,
    pub id: Option<String>,
    pub data: String,
    pub raw: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct SseDecoder {
    buffer: Vec<u8>,
    event: Option<String>,
    id: Option<String>,
    data: Vec<u8>,
    raw: Vec<u8>,
    event_bytes: usize,
    max_event_bytes: usize,
}

impl Default for SseDecoder {
    fn default() -> Self {
        Self::new(DEFAULT_MAX_SSE_EVENT_BYTES)
    }
}

impl SseDecoder {
    pub fn new(max_event_bytes: usize) -> Self {
        Self {
            buffer: Vec::new(),
            event: None,
            id: None,
            data: Vec::new(),
            raw: Vec::new(),
            event_bytes: 0,
            max_event_bytes: max_event_bytes.max(1),
        }
    }

    pub fn push(&mut self, chunk: &[u8]) -> Result<Vec<SseFrame>, OpenCodeError> {
        let mut frames = Vec::new();
        for byte in chunk {
            if self.event_bytes == self.max_event_bytes {
                return Err(OpenCodeError::FrameTooLarge {
                    limit: self.max_event_bytes,
                });
            }
            self.event_bytes += 1;
            self.buffer.push(*byte);
            if *byte != b'\n' {
                continue;
            }
            let line = std::mem::take(&mut self.buffer);
            let content = &line[..line.len() - 1];
            let content = content.strip_suffix(b"\r").unwrap_or(content);
            self.raw.extend_from_slice(&line);
            self.consume_line(content, &mut frames)?;
        }
        Ok(frames)
    }

    pub fn finish(&mut self) -> Result<Vec<SseFrame>, OpenCodeError> {
        let mut frames = Vec::new();
        if !self.buffer.is_empty() {
            let line = std::mem::take(&mut self.buffer);
            self.raw.extend_from_slice(&line);
            let line = line.strip_suffix(b"\r").unwrap_or(&line);
            self.consume_line(line, &mut frames)?;
        }
        if self.event.is_some() || self.id.is_some() || !self.data.is_empty() {
            if self.data.is_empty() {
                return Err(OpenCodeError::IncompleteSse);
            }
            frames.push(self.take_frame()?);
        }
        Ok(frames)
    }

    fn consume_line(
        &mut self,
        line: &[u8],
        frames: &mut Vec<SseFrame>,
    ) -> Result<(), OpenCodeError> {
        if line.is_empty() {
            if !self.data.is_empty() {
                frames.push(self.take_frame()?);
            } else {
                self.event = None;
                self.id = None;
                self.raw.clear();
                self.event_bytes = 0;
            }
            return Ok(());
        }
        if line[0] == b':' {
            return Ok(());
        }
        let split = line.iter().position(|byte| *byte == b':');
        let (field, value) = match split {
            Some(index) => (
                &line[..index],
                line[index + 1..]
                    .strip_prefix(b" ")
                    .unwrap_or(&line[index + 1..]),
            ),
            None => (line, &[][..]),
        };
        match field {
            b"event" => self.event = Some(Self::decode(value)?),
            b"id" => self.id = Some(Self::decode(value)?),
            b"data" => {
                if !self.data.is_empty() {
                    self.data.push(b'\n');
                }
                self.data.extend_from_slice(value);
            }
            _ => {}
        }
        Ok(())
    }

    fn decode(bytes: &[u8]) -> Result<String, OpenCodeError> {
        String::from_utf8(bytes.to_vec()).map_err(|_| OpenCodeError::InvalidUtf8)
    }

    fn take_frame(&mut self) -> Result<SseFrame, OpenCodeError> {
        let data = String::from_utf8(std::mem::take(&mut self.data))
            .map_err(|_| OpenCodeError::InvalidUtf8)?;
        let frame = SseFrame {
            event: self.event.take(),
            id: self.id.take(),
            data,
            raw: std::mem::take(&mut self.raw),
        };
        self.event_bytes = 0;
        Ok(frame)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handles_fragmented_utf8_and_crlf() {
        let mut decoder = SseDecoder::new(1024);
        let mut frames = decoder
            .push(b"event: message\r\ndata: {\"text\":\"")
            .unwrap();
        assert!(frames.is_empty());
        frames = decoder.push(&[0xF0, 0x9F]).unwrap();
        assert!(frames.is_empty());
        frames = decoder
            .push(&[0x98, 0x80, b'"', b'}', b'\r', b'\n', b'\r', b'\n'])
            .unwrap();
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].event.as_deref(), Some("message"));
        assert_eq!(frames[0].data, "{\"text\":\"😀\"}");
    }

    #[test]
    fn joins_multiple_data_lines_and_flushes_without_final_newline() {
        let mut decoder = SseDecoder::new(1024);
        assert!(decoder
            .push(b"data: {\"a\":1}\ndata: {\"b\":2}")
            .unwrap()
            .is_empty());
        let frames = decoder.finish().unwrap();
        assert_eq!(frames[0].data, "{\"a\":1}\n{\"b\":2}");
    }

    #[test]
    fn coalesced_and_fragmented_events_have_the_same_per_event_bound() {
        let chunk = b"data: {}\n\ndata: {}\n\n";
        let mut coalesced = SseDecoder::new(10);
        let expected = coalesced.push(chunk).unwrap();
        assert_eq!(expected.len(), 2);

        let mut fragmented = SseDecoder::new(10);
        let mut actual = Vec::new();
        for part in [
            &b"data: {}\n"[..],
            &b"\n"[..],
            &b"data: {}\n"[..],
            &b"\n"[..],
        ] {
            actual.extend(fragmented.push(part).unwrap());
        }
        assert_eq!(actual, expected);
    }

    #[test]
    fn oversized_event_is_rejected_before_the_next_byte_is_buffered() {
        let mut decoder = SseDecoder::new(10);
        let error = decoder.push(b"data: {}\ndata: {}\n\n").unwrap_err();
        assert!(matches!(error, OpenCodeError::FrameTooLarge { limit: 10 }));
    }

    #[test]
    fn unterminated_oversized_event_is_rejected() {
        let mut decoder = SseDecoder::new(10);
        let error = decoder.push(b"data: 12345").unwrap_err();
        assert!(matches!(error, OpenCodeError::FrameTooLarge { limit: 10 }));
    }
}
