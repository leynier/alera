use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

use super::relay_crypto::{
    IdentityKeyPair, RelayCryptoError, RelaySession, RelaySessionParameters,
};

pub const RELAY_HELLO_VERSION: u8 = 1;
const CLIENT_ID_BYTES: usize = 2;
const MAX_CLIENT_ID_BYTES: usize = 128;
const MAX_HANDSHAKE_BYTES: usize = 16 * 1024;
const FRAGMENT_MAGIC: &[u8; 5] = b"ALRF\x01";
const FRAGMENT_HEADER_BYTES: usize = FRAGMENT_MAGIC.len() + 4 + 4;
const RELAY_FRAGMENT_PAYLOAD_BYTES: usize = 48 * 1024;
const MAX_RELAY_ENVELOPE_BYTES: usize = 1024 * 1024;

#[derive(Default)]
pub struct FragmentReassembler {
    total: Option<usize>,
    bytes: Vec<u8>,
}

impl FragmentReassembler {
    pub fn accept(&mut self, payload: &[u8]) -> Result<Option<Vec<u8>>> {
        if !payload.starts_with(FRAGMENT_MAGIC) {
            if self.total.is_some() {
                self.reset();
                bail!("relay fragment sequence was interrupted");
            }
            return Ok(Some(payload.to_vec()));
        }
        if payload.len() <= FRAGMENT_HEADER_BYTES {
            self.reset();
            bail!("relay fragment is truncated");
        }
        let total = u32::from_be_bytes(payload[5..9].try_into()?) as usize;
        let offset = u32::from_be_bytes(payload[9..13].try_into()?) as usize;
        let chunk = &payload[FRAGMENT_HEADER_BYTES..];
        if total <= RELAY_FRAGMENT_PAYLOAD_BYTES
            || total > MAX_RELAY_ENVELOPE_BYTES
            || chunk.len() > RELAY_FRAGMENT_PAYLOAD_BYTES
            || offset
                .checked_add(chunk.len())
                .is_none_or(|end| end > total)
        {
            self.reset();
            bail!("relay fragment is outside the supported range");
        }
        if offset == 0 {
            self.total = Some(total);
            self.bytes.clear();
            self.bytes.reserve(total);
        } else if self.total != Some(total) || offset != self.bytes.len() {
            self.reset();
            bail!("relay fragment sequence is invalid");
        }
        self.bytes.extend_from_slice(chunk);
        if self.bytes.len() != total {
            return Ok(None);
        }
        self.total = None;
        Ok(Some(std::mem::take(&mut self.bytes)))
    }

    fn reset(&mut self) {
        self.total = None;
        self.bytes.clear();
    }
}

pub fn fragment(payload: &[u8]) -> Result<Vec<Vec<u8>>> {
    if payload.len() > MAX_RELAY_ENVELOPE_BYTES {
        bail!("relay envelope is too large");
    }
    if payload.len() <= RELAY_FRAGMENT_PAYLOAD_BYTES {
        return Ok(vec![payload.to_vec()]);
    }
    let total = u32::try_from(payload.len())?.to_be_bytes();
    Ok(payload
        .chunks(RELAY_FRAGMENT_PAYLOAD_BYTES)
        .enumerate()
        .map(|(index, chunk)| {
            let offset = u32::try_from(index * RELAY_FRAGMENT_PAYLOAD_BYTES)
                .expect("bounded relay fragment offset")
                .to_be_bytes();
            let mut frame = Vec::with_capacity(FRAGMENT_HEADER_BYTES + chunk.len());
            frame.extend_from_slice(FRAGMENT_MAGIC);
            frame.extend_from_slice(&total);
            frame.extend_from_slice(&offset);
            frame.extend_from_slice(chunk);
            frame
        })
        .collect())
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayHello {
    pub version: u8,
    pub account_id: String,
    pub runtime_id: String,
    pub client_id: String,
    pub key_version: i32,
    pub identity_public_key: String,
    pub ephemeral_public_key: String,
    pub nonce: String,
    pub grant: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayHelloAck {
    pub version: u8,
    pub runtime_id: String,
    pub client_id: String,
    pub identity_public_key: String,
    pub ephemeral_public_key: String,
    pub nonce: String,
    pub confirmation: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayConfirmation {
    pub version: u8,
    pub confirmation: String,
}

pub fn wrap(client_id: &str, payload: &[u8]) -> Result<Vec<u8>> {
    let client_id = client_id.as_bytes();
    if client_id.is_empty() || client_id.len() > MAX_CLIENT_ID_BYTES {
        bail!("relay client ID is outside the supported range");
    }
    let mut result = Vec::with_capacity(CLIENT_ID_BYTES + client_id.len() + payload.len());
    result.extend_from_slice(&(client_id.len() as u16).to_be_bytes());
    result.extend_from_slice(client_id);
    result.extend_from_slice(payload);
    Ok(result)
}

pub fn unwrap(frame: &[u8]) -> Result<(String, &[u8])> {
    if frame.len() < CLIENT_ID_BYTES {
        bail!("relay frame is truncated");
    }
    let client_id_len = u16::from_be_bytes([frame[0], frame[1]]) as usize;
    if client_id_len == 0
        || client_id_len > MAX_CLIENT_ID_BYTES
        || frame.len() < CLIENT_ID_BYTES + client_id_len
    {
        bail!("relay client ID is invalid");
    }
    let client_id =
        std::str::from_utf8(&frame[CLIENT_ID_BYTES..CLIENT_ID_BYTES + client_id_len])?.to_owned();
    Ok((client_id, &frame[CLIENT_ID_BYTES + client_id_len..]))
}

pub fn encode_json<T: Serialize>(value: &T) -> Result<Vec<u8>> {
    let encoded = serde_json::to_vec(value)?;
    if encoded.len() > MAX_HANDSHAKE_BYTES {
        bail!("relay handshake is too large");
    }
    Ok(encoded)
}

pub fn decode_json<T: for<'de> Deserialize<'de>>(payload: &[u8]) -> Result<T> {
    if payload.len() > MAX_HANDSHAKE_BYTES {
        bail!("relay handshake is too large");
    }
    Ok(serde_json::from_slice(payload)?)
}

pub fn derive_sessions(
    runtime_identity: &IdentityKeyPair,
    runtime_ephemeral: &IdentityKeyPair,
    client_static: [u8; 32],
    client_ephemeral: [u8; 32],
    runtime_id: &str,
    client_id: &str,
    nonce: &[u8],
) -> Result<(RelaySession, RelaySession), RelayCryptoError> {
    let parameters = RelaySessionParameters {
        local_static: runtime_identity,
        local_ephemeral: runtime_ephemeral,
        peer_static: client_static,
        peer_ephemeral: client_ephemeral,
        runtime_id,
        client_id,
        nonce,
        initiator: false,
    };
    let receive = RelaySession::derive(RelaySessionParameters { ..parameters })?;
    let send = RelaySession::derive(parameters)?;
    Ok((receive, send))
}

#[cfg(test)]
mod tests {
    use super::{fragment, unwrap, wrap, FragmentReassembler, MAX_RELAY_ENVELOPE_BYTES};

    #[test]
    fn outer_frame_keeps_client_identity_and_payload_boundaries() {
        let frame = wrap("mobile-1", b"payload").unwrap();
        let (client_id, payload) = unwrap(&frame).unwrap();
        assert_eq!(client_id, "mobile-1");
        assert_eq!(payload, b"payload");
    }

    #[test]
    fn outer_frame_rejects_invalid_identity_lengths() {
        assert!(unwrap(&[0, 0]).is_err());
        assert!(wrap("", b"payload").is_err());
    }

    #[test]
    fn large_envelopes_round_trip_through_fragments() {
        let payload = vec![7_u8; 70 * 1024];
        let fragments = fragment(&payload).unwrap();
        let mut reassembler = FragmentReassembler::default();
        let mut complete = None;
        for fragment in &fragments {
            complete = reassembler.accept(fragment).unwrap();
        }

        assert_eq!(fragments.len(), 2);
        assert_eq!(
            &fragments[0][..13],
            &[0x41, 0x4c, 0x52, 0x46, 0x01, 0, 1, 0x18, 0, 0, 0, 0, 0]
        );
        assert_eq!(complete.unwrap(), payload);
    }

    #[test]
    fn fragment_reassembly_rejects_oversized_and_out_of_order_input() {
        assert!(fragment(&vec![0_u8; MAX_RELAY_ENVELOPE_BYTES + 1]).is_err());
        let fragments = fragment(&vec![7_u8; 70 * 1024]).unwrap();
        let mut reassembler = FragmentReassembler::default();

        assert!(reassembler.accept(&fragments[1]).is_err());
    }
}
