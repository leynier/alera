use std::io;

use windows::core::PCWSTR;
use windows::Win32::Foundation::{LocalFree, HLOCAL};
use windows::Win32::Security::Cryptography::{
    CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
};
use zeroize::{Zeroize, Zeroizing};

pub(super) fn encode_key(key: &[u8]) -> io::Result<Zeroizing<Vec<u8>>> {
    crypt(key, true)
}
pub(super) fn decode_key(key: &[u8]) -> io::Result<Zeroizing<Vec<u8>>> {
    crypt(key, false)
}

fn crypt(bytes: &[u8], protect: bool) -> io::Result<Zeroizing<Vec<u8>>> {
    let mut input = Zeroizing::new(bytes.to_vec());
    let input_blob = CRYPT_INTEGER_BLOB {
        cbData: input
            .len()
            .try_into()
            .map_err(|_| io::Error::other("invalid credential length"))?,
        pbData: input.as_mut_ptr(),
    };
    let mut output = OwnedBlob(CRYPT_INTEGER_BLOB::default());
    // User-scoped DPAPI also protects a custom runtime directory whose
    // inherited ACL is broader than the default application-support folder.
    unsafe {
        if protect {
            CryptProtectData(
                &input_blob,
                PCWSTR::null(),
                None,
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output.0,
            )
        } else {
            CryptUnprotectData(
                &input_blob,
                None,
                None,
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output.0,
            )
        }
    }
    .map_err(|_| io::Error::other("desktop workflow credential protection failed"))?;
    if output.0.pbData.is_null() || output.0.cbData == 0 {
        return Err(io::Error::other("empty desktop workflow credential"));
    }
    Ok(Zeroizing::new(unsafe {
        std::slice::from_raw_parts(output.0.pbData, output.0.cbData as usize).to_vec()
    }))
}

struct OwnedBlob(CRYPT_INTEGER_BLOB);

impl Drop for OwnedBlob {
    fn drop(&mut self) {
        if !self.0.pbData.is_null() {
            unsafe {
                std::slice::from_raw_parts_mut(self.0.pbData, self.0.cbData as usize).zeroize();
                let _ = LocalFree(Some(HLOCAL(self.0.pbData.cast())));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workflow_windows_credential_is_protected_at_rest() {
        let key = [42; 32];
        let protected = encode_key(&key).unwrap();
        assert_ne!(protected.as_slice(), key);
        assert_eq!(decode_key(&protected).unwrap().as_slice(), key);
        assert!(decode_key(b"plaintext credential").is_err());
    }
}
