use chacha20poly1305::{
    aead::{Aead, Payload},
    ChaCha20Poly1305, KeyInit, Nonce,
};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::Zeroizing;

pub const RELAY_PROTOCOL_VERSION: u8 = 1;
pub const CLIENT_TO_RUNTIME: u8 = 0;
pub const RUNTIME_TO_CLIENT: u8 = 1;
const ENVELOPE_HEADER_BYTES: usize = 1 + 1 + 8 + 12;
const KEY_BYTES: usize = 32;

type HmacSha256 = Hmac<Sha256>;

#[derive(Clone)]
pub struct IdentityKeyPair {
    private: Zeroizing<[u8; KEY_BYTES]>,
    public: [u8; KEY_BYTES],
}

impl IdentityKeyPair {
    pub fn generate() -> Self {
        let secret = StaticSecret::random_from_rng(rand_core::OsRng);
        Self::from_private(secret.to_bytes())
    }

    pub fn from_private(private: [u8; KEY_BYTES]) -> Self {
        let secret = StaticSecret::from(private);
        Self {
            private: Zeroizing::new(private),
            public: PublicKey::from(&secret).to_bytes(),
        }
    }

    pub fn private_bytes(&self) -> [u8; KEY_BYTES] {
        *self.private
    }

    pub fn public_bytes(&self) -> [u8; KEY_BYTES] {
        self.public
    }

    fn secret(&self) -> StaticSecret {
        StaticSecret::from(*self.private)
    }
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum RelayCryptoError {
    #[error("invalid relay handshake transcript")]
    InvalidTranscript,
    #[error("invalid relay envelope")]
    InvalidEnvelope,
    #[error("relay envelope replay or counter gap")]
    Counter,
    #[error("relay envelope authentication failed")]
    Authentication,
}

#[derive(Clone, Copy)]
pub struct RelaySessionParameters<'a> {
    pub local_static: &'a IdentityKeyPair,
    pub local_ephemeral: &'a IdentityKeyPair,
    pub peer_static: [u8; KEY_BYTES],
    pub peer_ephemeral: [u8; KEY_BYTES],
    pub runtime_id: &'a str,
    pub client_id: &'a str,
    /// Fresh 16-byte handshake binding from a CSPRNG. This is not the ChaCha20-Poly1305 nonce.
    pub nonce: &'a [u8],
    pub initiator: bool,
}

pub struct RelaySession {
    send_key: [u8; KEY_BYTES],
    receive_key: [u8; KEY_BYTES],
    confirmation_key: [u8; KEY_BYTES],
    transcript_hash: [u8; KEY_BYTES],
    send_direction: u8,
    receive_direction: u8,
    next_send_counter: u64,
    next_receive_counter: u64,
}

impl RelaySession {
    pub fn derive(parameters: RelaySessionParameters<'_>) -> Result<Self, RelayCryptoError> {
        let RelaySessionParameters {
            local_static,
            local_ephemeral,
            peer_static,
            peer_ephemeral,
            runtime_id,
            client_id,
            nonce,
            initiator,
        } = parameters;
        if nonce.len() != 16
            || runtime_id.len() > u16::MAX as usize
            || client_id.len() > u16::MAX as usize
        {
            return Err(RelayCryptoError::InvalidTranscript);
        }
        let local_static_secret = local_static.secret();
        let local_ephemeral_secret = local_ephemeral.secret();
        let peer_static_public = PublicKey::from(peer_static);
        let peer_ephemeral_public = PublicKey::from(peer_ephemeral);
        let (initiator_static, responder_static, initiator_ephemeral, responder_ephemeral) =
            if initiator {
                (
                    local_static.public_bytes(),
                    peer_static,
                    local_ephemeral.public_bytes(),
                    peer_ephemeral,
                )
            } else {
                (
                    peer_static,
                    local_static.public_bytes(),
                    peer_ephemeral,
                    local_ephemeral.public_bytes(),
                )
            };
        let dh_static_static = local_static_secret.diffie_hellman(&peer_static_public);
        let dh_ephemeral_static = if initiator {
            local_ephemeral_secret.diffie_hellman(&peer_static_public)
        } else {
            local_static_secret.diffie_hellman(&peer_ephemeral_public)
        };
        let dh_static_ephemeral = if initiator {
            local_static_secret.diffie_hellman(&peer_ephemeral_public)
        } else {
            local_ephemeral_secret.diffie_hellman(&peer_static_public)
        };
        let dh_ephemeral_ephemeral = local_ephemeral_secret.diffie_hellman(&peer_ephemeral_public);
        if !dh_static_static.was_contributory()
            || !dh_ephemeral_static.was_contributory()
            || !dh_static_ephemeral.was_contributory()
            || !dh_ephemeral_ephemeral.was_contributory()
        {
            return Err(RelayCryptoError::InvalidTranscript);
        }
        let transcript = transcript(
            runtime_id,
            client_id,
            initiator_static,
            responder_static,
            initiator_ephemeral,
            responder_ephemeral,
            nonce,
        );
        let transcript_hash = Sha256::digest(&transcript);
        let mut ikm = Vec::with_capacity(4 * KEY_BYTES);
        ikm.extend_from_slice(dh_static_static.as_bytes());
        ikm.extend_from_slice(dh_ephemeral_static.as_bytes());
        ikm.extend_from_slice(dh_static_ephemeral.as_bytes());
        ikm.extend_from_slice(dh_ephemeral_ephemeral.as_bytes());
        let hkdf = Hkdf::<Sha256>::new(Some(b"alera-relay-v1"), &ikm);
        let mut send_key = [0_u8; KEY_BYTES];
        let mut receive_key = [0_u8; KEY_BYTES];
        let mut confirmation_key = [0_u8; KEY_BYTES];
        let send_label = if initiator {
            b"client-to-runtime"
        } else {
            b"runtime-to-client"
        };
        let receive_label = if initiator {
            b"runtime-to-client"
        } else {
            b"client-to-runtime"
        };
        expand_key(&hkdf, send_label, &transcript_hash, &mut send_key)?;
        expand_key(&hkdf, receive_label, &transcript_hash, &mut receive_key)?;
        expand_key(
            &hkdf,
            b"handshake-confirmation",
            &transcript_hash,
            &mut confirmation_key,
        )?;
        Ok(Self {
            send_key,
            receive_key,
            confirmation_key,
            transcript_hash: transcript_hash.into(),
            send_direction: if initiator {
                CLIENT_TO_RUNTIME
            } else {
                RUNTIME_TO_CLIENT
            },
            receive_direction: if initiator {
                RUNTIME_TO_CLIENT
            } else {
                CLIENT_TO_RUNTIME
            },
            next_send_counter: 0,
            next_receive_counter: 0,
        })
    }

    pub fn confirmation(&self) -> [u8; KEY_BYTES] {
        confirmation_for_key(
            &self.confirmation_key,
            &self.transcript_hash,
            confirmation_label(self.send_direction),
        )
    }

    pub fn verify_peer_confirmation(&self, confirmation: &[u8]) -> Result<(), RelayCryptoError> {
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&self.confirmation_key)
            .expect("HMAC accepts every key length");
        update_confirmation_mac(
            &mut mac,
            &self.transcript_hash,
            confirmation_label(self.receive_direction),
        );
        mac.verify_slice(confirmation)
            .map_err(|_| RelayCryptoError::Authentication)
    }

    pub fn seal(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, RelayCryptoError> {
        let counter = self.next_send_counter;
        let nonce = nonce(self.send_direction, counter);
        let aad = associated_data(self.send_direction, counter, &self.transcript_hash);
        let cipher = ChaCha20Poly1305::new_from_slice(&self.send_key)
            .map_err(|_| RelayCryptoError::InvalidEnvelope)?;
        let ciphertext = cipher
            .encrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: plaintext,
                    aad: &aad,
                },
            )
            .map_err(|_| RelayCryptoError::Authentication)?;
        self.next_send_counter = counter.checked_add(1).ok_or(RelayCryptoError::Counter)?;
        let mut result = Vec::with_capacity(ENVELOPE_HEADER_BYTES + ciphertext.len());
        result.push(RELAY_PROTOCOL_VERSION);
        result.push(self.send_direction);
        result.extend_from_slice(&counter.to_be_bytes());
        result.extend_from_slice(&nonce);
        result.extend_from_slice(&ciphertext);
        Ok(result)
    }

    pub fn open(&mut self, envelope: &[u8]) -> Result<Vec<u8>, RelayCryptoError> {
        if envelope.len() < ENVELOPE_HEADER_BYTES + 16
            || envelope[0] != RELAY_PROTOCOL_VERSION
            || envelope[1] != self.receive_direction
        {
            return Err(RelayCryptoError::InvalidEnvelope);
        }
        let counter = u64::from_be_bytes(
            envelope[2..10]
                .try_into()
                .map_err(|_| RelayCryptoError::InvalidEnvelope)?,
        );
        if counter != self.next_receive_counter {
            return Err(RelayCryptoError::Counter);
        }
        let expected_nonce = nonce(self.receive_direction, counter);
        if envelope[10..22] != expected_nonce {
            return Err(RelayCryptoError::InvalidEnvelope);
        }
        let aad = associated_data(self.receive_direction, counter, &self.transcript_hash);
        let cipher = ChaCha20Poly1305::new_from_slice(&self.receive_key)
            .map_err(|_| RelayCryptoError::InvalidEnvelope)?;
        let plaintext = cipher
            .decrypt(
                Nonce::from_slice(&expected_nonce),
                Payload {
                    msg: &envelope[ENVELOPE_HEADER_BYTES..],
                    aad: &aad,
                },
            )
            .map_err(|_| RelayCryptoError::Authentication)?;
        self.next_receive_counter = counter.checked_add(1).ok_or(RelayCryptoError::Counter)?;
        Ok(plaintext)
    }
}

fn expand_key(
    hkdf: &Hkdf<Sha256>,
    label: &[u8],
    transcript_hash: &[u8],
    output: &mut [u8; KEY_BYTES],
) -> Result<(), RelayCryptoError> {
    let mut info = Vec::with_capacity(label.len() + transcript_hash.len() + 1);
    info.extend_from_slice(b"alera-relay-key:");
    info.extend_from_slice(label);
    info.extend_from_slice(transcript_hash);
    hkdf.expand(&info, output)
        .map_err(|_| RelayCryptoError::InvalidTranscript)
}

fn confirmation_for_key(
    key: &[u8; KEY_BYTES],
    transcript_hash: &[u8; KEY_BYTES],
    role: &[u8],
) -> [u8; KEY_BYTES] {
    let mut mac = <HmacSha256 as Mac>::new_from_slice(key).expect("HMAC accepts every key length");
    update_confirmation_mac(&mut mac, transcript_hash, role);
    mac.finalize().into_bytes().into()
}

fn update_confirmation_mac(mac: &mut HmacSha256, transcript_hash: &[u8; KEY_BYTES], role: &[u8]) {
    mac.update(b"alera-relay-confirmation:");
    mac.update(role);
    mac.update(b":");
    mac.update(transcript_hash);
}

fn confirmation_label(direction: u8) -> &'static [u8] {
    if direction == CLIENT_TO_RUNTIME {
        b"client"
    } else {
        b"runtime"
    }
}

fn transcript(
    runtime_id: &str,
    client_id: &str,
    initiator_static: [u8; KEY_BYTES],
    responder_static: [u8; KEY_BYTES],
    initiator_ephemeral: [u8; KEY_BYTES],
    responder_ephemeral: [u8; KEY_BYTES],
    nonce: &[u8],
) -> Vec<u8> {
    let mut result = Vec::with_capacity(128 + runtime_id.len() + client_id.len());
    result.extend_from_slice(b"ALERA-RELAY-HANDSHAKE-V1");
    result.extend_from_slice(&(runtime_id.len() as u16).to_be_bytes());
    result.extend_from_slice(runtime_id.as_bytes());
    result.extend_from_slice(&(client_id.len() as u16).to_be_bytes());
    result.extend_from_slice(client_id.as_bytes());
    result.extend_from_slice(&initiator_static);
    result.extend_from_slice(&responder_static);
    result.extend_from_slice(&initiator_ephemeral);
    result.extend_from_slice(&responder_ephemeral);
    result.extend_from_slice(nonce);
    result
}

fn nonce(direction: u8, counter: u64) -> [u8; 12] {
    let mut result = [0_u8; 12];
    result[0] = direction;
    result[4..].copy_from_slice(&counter.to_be_bytes());
    result
}

fn associated_data(direction: u8, counter: u64, transcript_hash: &[u8; KEY_BYTES]) -> Vec<u8> {
    let mut result = Vec::with_capacity(1 + 1 + 8 + KEY_BYTES);
    result.push(RELAY_PROTOCOL_VERSION);
    result.push(direction);
    result.extend_from_slice(&counter.to_be_bytes());
    result.extend_from_slice(transcript_hash);
    result
}

#[cfg(test)]
mod tests {
    use super::{IdentityKeyPair, RelayCryptoError, RelaySession, RelaySessionParameters};

    fn pair(seed: u8) -> IdentityKeyPair {
        IdentityKeyPair::from_private([seed; 32])
    }

    fn handshake_nonce() -> [u8; 16] {
        let high = u128::from(rand_core::RngCore::next_u64(&mut rand_core::OsRng));
        let low = u128::from(rand_core::RngCore::next_u64(&mut rand_core::OsRng));
        ((high << 64) | low).to_be_bytes()
    }

    fn session(parameters: RelaySessionParameters<'_>) -> RelaySession {
        RelaySession::derive(parameters).unwrap()
    }

    #[test]
    fn both_directions_derive_the_same_transcript_keys() {
        let client_static = pair(1);
        let runtime_static = pair(2);
        let client_ephemeral = pair(3);
        let runtime_ephemeral = pair(4);
        let nonce = handshake_nonce();
        let mut client = session(RelaySessionParameters {
            local_static: &client_static,
            local_ephemeral: &client_ephemeral,
            peer_static: runtime_static.public_bytes(),
            peer_ephemeral: runtime_ephemeral.public_bytes(),
            runtime_id: "runtime",
            client_id: "mobile",
            nonce: &nonce,
            initiator: true,
        });
        let mut runtime = session(RelaySessionParameters {
            local_static: &runtime_static,
            local_ephemeral: &runtime_ephemeral,
            peer_static: client_static.public_bytes(),
            peer_ephemeral: client_ephemeral.public_bytes(),
            runtime_id: "runtime",
            client_id: "mobile",
            nonce: &nonce,
            initiator: false,
        });
        let message = b"opaque relay payload";
        let envelope = client.seal(message).unwrap();
        assert_eq!(runtime.open(&envelope).unwrap(), message);
        let reply = runtime.seal(b"reply").unwrap();
        assert_eq!(client.open(&reply).unwrap(), b"reply");
        assert!(runtime
            .verify_peer_confirmation(&client.confirmation())
            .is_ok());
        assert!(client
            .verify_peer_confirmation(&runtime.confirmation())
            .is_ok());
        assert_eq!(
            runtime.verify_peer_confirmation(&runtime.confirmation()),
            Err(RelayCryptoError::Authentication)
        );
    }

    #[test]
    fn replay_truncation_corruption_and_wrong_peer_are_rejected() {
        let client_static = pair(11);
        let runtime_static = pair(12);
        let client_ephemeral = pair(13);
        let runtime_ephemeral = pair(14);
        let nonce = handshake_nonce();
        let derive_client = || {
            session(RelaySessionParameters {
                local_static: &client_static,
                local_ephemeral: &client_ephemeral,
                peer_static: runtime_static.public_bytes(),
                peer_ephemeral: runtime_ephemeral.public_bytes(),
                runtime_id: "runtime",
                client_id: "mobile",
                nonce: &nonce,
                initiator: true,
            })
        };
        let derive_runtime = || {
            session(RelaySessionParameters {
                local_static: &runtime_static,
                local_ephemeral: &runtime_ephemeral,
                peer_static: client_static.public_bytes(),
                peer_ephemeral: client_ephemeral.public_bytes(),
                runtime_id: "runtime",
                client_id: "mobile",
                nonce: &nonce,
                initiator: false,
            })
        };
        let mut client = derive_client();
        let mut runtime = derive_runtime();
        let envelope = client.seal(b"payload").unwrap();
        assert!(runtime.open(&envelope).is_ok());
        assert_eq!(runtime.open(&envelope), Err(RelayCryptoError::Counter));
        let mut truncated_runtime = derive_runtime();
        assert_eq!(
            truncated_runtime.open(&envelope[..envelope.len() - 1]),
            Err(RelayCryptoError::Authentication)
        );
        let mut corrupt = envelope.clone();
        corrupt[22] ^= 1;
        let mut corrupt_runtime = derive_runtime();
        assert_eq!(
            corrupt_runtime.open(&corrupt),
            Err(RelayCryptoError::Authentication)
        );

        let wrong = pair(99);
        let mut wrong_runtime = session(RelaySessionParameters {
            local_static: &wrong,
            local_ephemeral: &runtime_ephemeral,
            peer_static: client_static.public_bytes(),
            peer_ephemeral: client_ephemeral.public_bytes(),
            runtime_id: "runtime",
            client_id: "mobile",
            nonce: &nonce,
            initiator: false,
        });
        assert_eq!(
            wrong_runtime.open(&envelope),
            Err(RelayCryptoError::Authentication)
        );
    }
}

#[cfg(test)]
#[path = "relay_crypto_fixed_vectors.rs"]
mod fixed_vector_tests;
