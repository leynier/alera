use super::{IdentityKeyPair, RelaySession, RelaySessionParameters};

fn pair(seed: u8) -> IdentityKeyPair {
    IdentityKeyPair::from_private([seed; 32])
}

/// Handshake binding shared with `mobile/test/relay_crypto_test.dart`.
/// Known-answer tests require a fixed value; production generates this with a CSPRNG.
fn interop_handshake_binding() -> [u8; 16] {
    // codeql[rust/hard-coded-cryptographic-value]
    let bytes = hex::decode("05050505050505050505050505050505").expect("valid fixture hex");
    bytes.try_into().expect("fixture is 16 bytes")
}

#[test]
fn fixed_vector_matches_the_interoperability_fixture() {
    let client_static = pair(1);
    let runtime_static = pair(2);
    let client_ephemeral = pair(3);
    let runtime_ephemeral = pair(4);
    let nonce = interop_handshake_binding();
    let mut client = RelaySession::derive(RelaySessionParameters {
        local_static: &client_static,
        local_ephemeral: &client_ephemeral,
        peer_static: runtime_static.public_bytes(),
        peer_ephemeral: runtime_ephemeral.public_bytes(),
        runtime_id: "runtime",
        client_id: "mobile",
        nonce: &nonce,
        initiator: true,
    })
    .unwrap();
    let runtime = RelaySession::derive(RelaySessionParameters {
        local_static: &runtime_static,
        local_ephemeral: &runtime_ephemeral,
        peer_static: client_static.public_bytes(),
        peer_ephemeral: client_ephemeral.public_bytes(),
        runtime_id: "runtime",
        client_id: "mobile",
        nonce: &nonce,
        initiator: false,
    })
    .unwrap();
    assert_eq!(
        client.confirmation(),
        [
            0xc8, 0x0f, 0xa6, 0xa2, 0xb6, 0x7d, 0x10, 0xab, 0x0c, 0xc3, 0x78, 0x66, 0x17, 0x50,
            0xb9, 0x2e, 0xea, 0x31, 0x1c, 0x12, 0xc3, 0x29, 0x15, 0x64, 0xcc, 0xec, 0x29, 0x98,
            0xd1, 0x06, 0xc2, 0xf8,
        ]
    );
    assert_eq!(
        runtime.confirmation(),
        [
            0xc1, 0x6d, 0x0c, 0x27, 0x57, 0xcd, 0x97, 0xa6, 0xde, 0x1d, 0xf0, 0x97, 0x4a, 0x0d,
            0xad, 0x18, 0xd2, 0xdd, 0xba, 0x76, 0xcd, 0x67, 0x80, 0xfd, 0xbc, 0x80, 0x4a, 0x86,
            0xdd, 0x21, 0x3c, 0x74,
        ]
    );
    assert_eq!(
        client.seal(b"fixed vector").unwrap(),
        [
            0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xcc, 0x8e, 0x89, 0xf9, 0xf0, 0x93,
            0x32, 0x8b, 0xe9, 0xb6, 0x41, 0x29, 0xb1, 0x32, 0xa5, 0x63, 0xee, 0x42, 0xf1, 0x5b,
            0xdb, 0x63, 0xc1, 0x41, 0xb7, 0x6c, 0x9b, 0xdb,
        ]
    );
}
