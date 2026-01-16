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

pub fn decrypt_password(encrypted_json: &str, salt: &str) -> anyhow::Result<String> {
    if encrypted_json.is_empty() {
        return Ok(String::new());
    }

    // Try JSON format first
    let encrypted_data: EncryptedData = match serde_json::from_str(encrypted_json) {
        Ok(data) => data,
        Err(_) => {
            // Legacy fallback: base64 or plain text
            return match BASE64.decode(encrypted_json) {
                Ok(bytes) => Ok(String::from_utf8(bytes)?),
                Err(_) => Ok(encrypted_json.to_string()),
            };
        }
    };

    let key = derive_key(salt);

    let iv = BASE64.decode(&encrypted_data.iv)?;
    if iv.len() != 16 {
        anyhow::bail!("invalid IV length: {}", iv.len());
    }

    let ciphertext = BASE64.decode(&encrypted_data.data)?;

    let decryptor = Aes256CbcDec::new(&key.into(), iv.as_slice().into());
    let mut buf = ciphertext;

    let plaintext = decryptor
        .decrypt_padded_mut::<block_padding::Pkcs7>(&mut buf)
        .map_err(|e| anyhow::anyhow!(e))?;

    Ok(String::from_utf8(plaintext.to_vec())?)
}


pub fn generate_salt() -> String {
    let mut salt = [0u8; 16];
    rand::rng().fill_bytes(&mut salt);
    BASE64.encode(salt)
}
