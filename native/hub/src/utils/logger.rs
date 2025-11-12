use rinf::{DartSignal, RustSignal, SignalPiece};
use crate::signals::LogSignal;

fn _log(level: &str, message: &str) {
    LogSignal {
        level: level.to_string(),
        message: message.to_string(),
    }
    .send_signal_to_dart();
}

pub fn debug(message: &str) {
    _log("DEBUG", message);
}

pub fn error(message: &str) {
    _log("ERROR", message);
}
