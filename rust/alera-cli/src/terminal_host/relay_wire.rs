use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

use super::relay_crypto::{
    IdentityKeyPair, RelayCryptoError, RelaySession, RelaySessionParameters,
};

pub const RELAY_HELLO_VERSION: u8 = 1;
const CLIENT_ID_BYTES: usize = 2;
const MAX_CLIENT_ID_BYTES: usize = 128;
const MAX_HANDSHAKE_BYTES: usize = 16 * 1024;

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
    use super::{unwrap, wrap};

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
}
