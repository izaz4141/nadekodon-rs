extern crate nadekodon_core as core;
use core::utils::security::{encrypt_password, decrypt_password, generate_salt};
use crate::signals::*;
use crate::utils::logger;
use rinf::{DartSignal, RustSignal};

pub async fn handle_password_security() {
    let encrypt_receiver = EncryptPassword::get_dart_signal_receiver();
    let decrypt_receiver = DecryptPassword::get_dart_signal_receiver();
    let salt_receiver = GenerateSalt::get_dart_signal_receiver();

    loop {
        tokio::select! {
            Some(signal_pack) = encrypt_receiver.recv() => {
                let signal = signal_pack.message;
                let encrypted = encrypt_password(&signal.plain_text, &signal.salt).ok();
                EncryptionOutput {
                    id: signal.id,
                    encrypted_text: encrypted,
                }
                .send_signal_to_dart();
            }
            Some(signal_pack) = decrypt_receiver.recv() => {
                let signal = signal_pack.message;
                let decrypted = match decrypt_password(&signal.encrypted_text, &signal.salt) {
                    Ok(decrypted) => decrypted,
                    Err(e) => {
                        logger::error(&format!("Failed to decrypt password: {}", e));
                        continue;
                    },
                };
                DecryptionOutput {
                    id: signal.id,
                    plain_text: Some(decrypted),
                }
                .send_signal_to_dart();
            }
            Some(signal_pack) = salt_receiver.recv() => {
                let salt = generate_salt();
                SaltOutput {
                    id: signal_pack.message.id,
                    salt,
                }
                .send_signal_to_dart();
            }
        }
    }
}
