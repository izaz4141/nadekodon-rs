use aes_gcm_siv::{
    Aes256GcmSiv, Nonce,
    aead::{Aead, KeyInit, OsRng, rand_core::RngCore},
};

const NONCE_SIZE: usize = 12;

pub fn generate_master_key() -> String {
    let mut key = [0u8; 32];
    OsRng.fill_bytes(&mut key);
    hex::encode(key)
}

pub fn is_valid_master_key(key: &str) -> bool {
    if key.len() != 64 {
        return false;
    }
    hex::decode(key).map(|b| b.len() == 32).unwrap_or(false)
}

pub fn valid_encryption_format(ciphertext: &str) -> bool {
    if !ciphertext.starts_with("NDK:") {
        return false;
    }
    hex::decode(&ciphertext[4..]).is_ok()
}

pub fn encrypt(plaintext: &str, master_key: &str) -> Result<String, String> {
    let key_bytes = hex::decode(master_key).map_err(|e| e.to_string())?;
    if key_bytes.len() != 32 {
        return Err("Invalid master key length".to_string());
    }

    let cipher = Aes256GcmSiv::new_from_slice(&key_bytes).map_err(|e| e.to_string())?;

    let mut nonce_bytes = [0u8; NONCE_SIZE];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, plaintext.as_bytes())
        .map_err(|e| e.to_string())?;

    let mut result = nonce_bytes.to_vec();
    result.extend(ciphertext);

    Ok(format!("NDK:{}", hex::encode(result)))
}

pub fn decrypt(ciphertext: &str, master_key: &str) -> Result<String, String> {
    if !valid_encryption_format(ciphertext) {
        return Err("Invalid encryption format".to_string());
    }

    let data = hex::decode(&ciphertext[4..]).map_err(|e| e.to_string())?;

    if data.len() < NONCE_SIZE {
        return Err("Invalid ciphertext".to_string());
    }

    let key_bytes = hex::decode(master_key).map_err(|e| e.to_string())?;
    if key_bytes.len() != 32 {
        return Err("Invalid master key length".to_string());
    }

    let cipher = Aes256GcmSiv::new_from_slice(&key_bytes).map_err(|e| e.to_string())?;

    let nonce = Nonce::from_slice(&data[..NONCE_SIZE]);
    let ciphertext_bytes = &data[NONCE_SIZE..];

    let plaintext = cipher
        .decrypt(nonce, ciphertext_bytes)
        .map_err(|e| e.to_string())?;

    String::from_utf8(plaintext).map_err(|e| e.to_string())
}
