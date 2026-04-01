use crate::signals::LogSignal;
use rinf::RustSignal;

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

pub fn info(message: &str) {
    _log("INFO", message);
}

pub fn warn(message: &str) {
    _log("WARN", message);
}
