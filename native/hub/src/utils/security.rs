extern crate nadekodon_core as core;
use crate::signals::{
    GenerateSalt, HashPassword, HashingOutput, Login, LoginResult, SaltOutput, VerifyPassword,
    VerifyPasswordResult,
};
use crate::utils::logger;
use core::utils::security::{generate_salt, hash_password, validate_password};
use rinf::{DartSignal, RustSignal};

pub async fn handle_password_security() {
    let encrypt_receiver = HashPassword::get_dart_signal_receiver();
    let salt_receiver = GenerateSalt::get_dart_signal_receiver();

    loop {
        tokio::select! {
            Some(signal_pack) = encrypt_receiver.recv() => {
                let signal = signal_pack.message;
                let hashed = match hash_password(&signal.plain_text, &signal.salt) {
                    Ok(v) => v,
                    Err(e) => {
                        logger::error(&format!("Error when hashing password: {:?}", e));
                        signal.plain_text
                    }
                };
                HashingOutput {
                    id: signal.id,
                    hashed_text: Some(hashed),
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

pub async fn handle_login() {
    let receiver = Login::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let msg = signal_pack.message;

        let success =
            validate_password(&msg.rpass, &msg.ipass).unwrap_or(false) & (msg.iuser == msg.ruser);

        LoginResult {
            id: msg.id.clone(),
            success,
        }
        .send_signal_to_dart();
    }
}

pub async fn verify_pass() {
    let receiver = VerifyPassword::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let msg = signal_pack.message;
        let success = validate_password(&msg.reference, &msg.input).unwrap_or(false);

        VerifyPasswordResult {
            id: msg.id.clone(),
            success: success,
        }
        .send_signal_to_dart();
    }
}
