use anyhow::Result;
use argon2::{
    Argon2,
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString, rand_core::OsRng},
};

pub fn generate_salt() -> String {
    SaltString::generate(&mut OsRng).as_str().to_string()
}

pub fn hash_password(password: &str, salt: &str) -> Result<String> {
    if PasswordHash::new(password).is_ok() {
        return Ok(password.to_string());
    };
    let salt_string =
        SaltString::from_b64(salt).map_err(|e| anyhow::anyhow!("Invalid salt format: {}", e))?;

    let argon2 = Argon2::default();

    let password_hash = argon2
        .hash_password(password.as_bytes(), &salt_string)
        .map_err(|e| anyhow::anyhow!("Argon2 hashing failed: {}", e))?;

    Ok(password_hash.to_string())
}

pub fn validate_password(stored_hash: &str, input_password: &str) -> Result<bool> {
    let parsed_hash = match PasswordHash::new(stored_hash) {
        Ok(h) => h,
        Err(_) => {
            if input_password == stored_hash {
                return Ok(true);
            }
            return Err(anyhow::anyhow!("Invalid password hash format"));
        }
    };

    let argon2 = Argon2::default();

    Ok(argon2
        .verify_password(input_password.as_bytes(), &parsed_hash)
        .is_ok())
}

pub fn is_valid_hash(input: &str) -> bool {
    PasswordHash::new(input).is_ok()
}
