use aes::cipher::{BlockDecryptMut, BlockEncryptMut, KeyIvInit, block_padding};
use cbc::{Decryptor, Encryptor};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use rand::{RngCore}; // Import Rng trait to access fill_bytes

type Aes256CbcEnc = Encryptor<aes::Aes256>;
type Aes256CbcDec = Decryptor<aes::Aes256>;

const PEPPER_PREFIX: &str = "nadekodon_secret_pepper_";

#[derive(Serialize, Deserialize)]
struct EncryptedData {
    iv: String,
    data: String,
}

fn derive_key(salt: &str) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(format!("{}{}", PEPPER_PREFIX, salt).as_bytes());
    hasher.finalize().into()
}

pub fn encrypt_password(password: &str, salt: &str) -> anyhow::Result<String> {
    if password.is_empty() {
        return Ok(String::new());
    }

    let key = derive_key(salt);
    let mut iv = [0u8; 16];
    rand::rng().fill_bytes(&mut iv);

    let encryptor = Aes256CbcEnc::new(&key.into(), &iv.into());
    let len = password.len();
    let block_len = 16;
    let final_len = len + (block_len - (len % block_len));
    let mut buf = vec![0u8; final_len];
    buf[..len].copy_from_slice(password.as_bytes());

    let ciphertext_slice = encryptor.encrypt_padded_mut::<aes::cipher::block_padding::Pkcs7>(&mut buf, len)
        .map_err(|e| anyhow::anyhow!("Encryption failed: {:?}", e))?;
    
    let encrypted_data = EncryptedData {
        iv: BASE64.encode(iv),
        data: BASE64.encode(ciphertext_slice),
    };

    Ok(serde_json::to_string(&encrypted_data)?)
}

pub fn decrypt_password(encrypted_json: &str, salt: &str) -> Option<String> {
    if encrypted_json.is_empty() {
        return Some(String::new());
    }

    // Attempt to parse as JSON first
    let encrypted_data: EncryptedData = match serde_json::from_str(encrypted_json) {
        Ok(data) => data,
        Err(_) => {
             // Fallback: try plain base64 decode (legacy/fallback mentioned in dart)
             return match BASE64.decode(encrypted_json) {
                 Ok(bytes) => String::from_utf8(bytes).ok(),
                 Err(_) => Some(encrypted_json.to_string()), // Treat as plain text if all else fails? Dart does `return stored`
             };
        }
    };

    let key = derive_key(salt);
    
    let iv = BASE64.decode(&encrypted_data.iv).ok()?;
    if iv.len() != 16 { return None; }
    
    let ciphertext = BASE64.decode(&encrypted_data.data).ok()?;

    let decryptor = Aes256CbcDec::new(&key.into(), iv.as_slice().into());
    
    // Clone ciphertext effectively by making it mutable if we owned it, 
    // but here we just use the vector we decoded.
    let mut buf = ciphertext;
    
    match decryptor.decrypt_padded_mut::<block_padding::Pkcs7>(&mut buf) {
        Ok(plaintext) => String::from_utf8(plaintext.to_vec()).ok(),
        Err(_) => None,
    }
}

pub fn generate_salt() -> String {
    let mut salt = [0u8; 16];
    rand::rng().fill_bytes(&mut salt);
    BASE64.encode(salt)
}
