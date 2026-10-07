use anyhow::Result;
use serde_json::Value;
use std::{
    path::{Path, PathBuf},
    sync::Arc,
    time::UNIX_EPOCH,
};

use crate::utils::encryption::{decrypt, encrypt, valid_encryption_format};
use crate::utils::logger;

/// Default config JSON, embedded so it works from any working directory.
const DEFAULT_CONFIG_JSON: &str = include_str!("../../../../assets/docs/default.json");

/// Sample API key from default.json; never a usable credential.
pub const SAMPLE_API_KEY: &str = "aReallylongR4ndomsTring";

/// Config keys holding secrets or device-local state; never sent to clients.
pub const PRIVATE_CONFIG_KEYS: &[&str] = &["username", "password", "server_api_key", "accounts"];

/// Config keys encrypted at rest with the master key.
const ENCRYPTED_CONFIG_KEYS: &[&str] = &["server_api_key"];

/// Returns a deep copy of `value` with every key listed in `keys` removed.
pub fn strip_keys(value: &Value, keys: &[&str]) -> Value {
    match value {
        Value::Object(map) => {
            let mut out = serde_json::Map::with_capacity(map.len());
            for (k, v) in map {
                if keys.contains(&k.as_str()) {
                    continue;
                }
                out.insert(k.clone(), strip_keys(v, keys));
            }
            Value::Object(out)
        }
        Value::Array(items) => Value::Array(items.iter().map(|i| strip_keys(i, keys)).collect()),
        other => other.clone(),
    }
}

/// In-memory representation of `config.json`; secrets are held decrypted
/// and re-encrypted on write.
pub struct AppConfig {
    pub value: Value,
    pub path: PathBuf,
    pub mtime: u64,
}

async fn file_mtime(path: &Path) -> Result<u64> {
    let metadata = tokio::fs::metadata(path).await?;
    let modified = metadata.modified()?;
    Ok(modified.duration_since(UNIX_EPOCH)?.as_secs())
}

/// Decrypts every at-rest secret in `value` using `master_key`.
fn decrypt_secrets(value: &mut Value, master_key: &str) {
    for key in ENCRYPTED_CONFIG_KEYS {
        if let Some(encrypted) = value.get(key).and_then(|v| v.as_str())
            && valid_encryption_format(encrypted)
            && let Ok(plain) = decrypt(encrypted, master_key)
        {
            value[*key] = Value::String(plain);
        }
    }

    if let Some(accounts) = value
        .get_mut("accounts")
        .and_then(|v| v.as_array_mut())
    {
        for account in accounts.iter_mut() {
            if let Some(encrypted) = account.get("api_key").and_then(|v| v.as_str())
                && valid_encryption_format(encrypted)
                && let Ok(plain) = decrypt(encrypted, master_key)
            {
                account["api_key"] = Value::String(plain);
            }
        }
    }
}

/// Encrypts every secret in `value` not already encrypted.
fn encrypt_secrets(value: &mut Value, master_key: &str) {
    for key in ENCRYPTED_CONFIG_KEYS {
        if let Some(plain) = value.get(key).and_then(|v| v.as_str())
            && !plain.is_empty()
            && !valid_encryption_format(plain)
            && let Ok(encrypted) = encrypt(plain, master_key)
        {
            value[*key] = Value::String(encrypted);
        }
    }

    if let Some(accounts) = value
        .get_mut("accounts")
        .and_then(|v| v.as_array_mut())
    {
        for account in accounts.iter_mut() {
            if let Some(plain) = account.get("api_key").and_then(|v| v.as_str())
                && !plain.is_empty()
                && !valid_encryption_format(plain)
                && let Ok(encrypted) = encrypt(plain, master_key)
            {
                account["api_key"] = Value::String(encrypted);
            }
        }
    }
}

/// Writes `contents` to `path` atomically (temp file + rename).
async fn write_atomic(path: &Path, contents: &str) -> Result<()> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    let mut tmp_name = path.as_os_str().to_owned();
    tmp_name.push(".tmp");
    let tmp_path = PathBuf::from(tmp_name);
    tokio::fs::write(&tmp_path, contents).await?;
    tokio::fs::rename(&tmp_path, path).await?;
    Ok(())
}

/// Loads the config file at `path`, decrypting secrets in memory.
pub async fn load_config(path: String, master_key: String) -> Result<Arc<AppConfig>> {
    let config_path = PathBuf::from(&path);
    if !config_path.is_file() {
        anyhow::bail!("Config file does not exist: {}", path);
    }

    let contents = tokio::fs::read_to_string(&config_path).await?;
    let mut config_value: Value = serde_json::from_str(&contents)?;
    if !config_value.is_object() {
        anyhow::bail!("Config file is not a JSON object: {}", path);
    }
    decrypt_secrets(&mut config_value, &master_key);

    let mtime = file_mtime(&config_path).await?;
    Ok(Arc::new(AppConfig {
        value: config_value,
        path: config_path,
        mtime,
    }))
}

/// Loads the config at `path`, bootstrapping embedded defaults when missing.
/// Returns `(config, first_run)`.
pub async fn load_or_bootstrap(path: String, master_key: String) -> Result<(Arc<AppConfig>, bool)> {
    match load_config(path.clone(), master_key).await {
        Ok(app_config) => Ok((app_config, false)),
        Err(e) => {
            logger::warn(&format!(
                "Can't load config at {}: {}; creating a default one",
                path, e
            ));
            Ok((load_default_config(path).await?, true))
        }
    }
}

/// Merges a JSON object encoded as text into `value`; non-objects rejected.
pub fn merge_settings_json(value: &mut Value, settings_json: &str) -> Result<()> {
    let patch: serde_json::Map<String, Value> = serde_json::from_str(settings_json)?;
    for (k, v) in patch {
        value[k] = v;
    }
    Ok(())
}

/// Persists `settings` to `path`, encrypting secrets; written atomically.
pub async fn save_config(path: &Path, settings: &Value, master_key: &str) -> Result<()> {
    let mut new_settings = settings.clone();
    encrypt_secrets(&mut new_settings, master_key);
    let json_str = serde_json::to_string_pretty(&new_settings)?;
    write_atomic(path, &json_str).await
}

/// Writes the embedded default config to `path` (first run bootstrap).
pub async fn load_default_config(path: String) -> Result<Arc<AppConfig>> {
    let config_path = PathBuf::from(&path);
    let mut config_value: Value = serde_json::from_str(DEFAULT_CONFIG_JSON)?;
    if !config_value.is_object() {
        anyhow::bail!("Embedded default config is not a JSON object");
    }
    // Blank the sample key; it must never be usable.
    if config_value["server_api_key"].as_str() == Some(SAMPLE_API_KEY) {
        config_value["server_api_key"] = Value::String(String::new());
    }

    let json_str = serde_json::to_string_pretty(&config_value)?;
    write_atomic(&config_path, &json_str).await?;

    let mtime = file_mtime(&config_path).await?;
    Ok(Arc::new(AppConfig {
        value: config_value,
        path: config_path,
        mtime,
    }))
}
