use std::sync::OnceLock;
use time::{OffsetDateTime, macros::format_description};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Level {
    Debug,
    Info,
    Warn,
    Error,
}

static LEVEL: OnceLock<Level> = OnceLock::new();

fn threshold() -> Level {
    *LEVEL.get_or_init(|| {
        match std::env::var("NADEKO_LOG_LEVEL") {
            Ok(value) => match value.trim().to_ascii_lowercase().as_str() {
                "debug" => Level::Debug,
                "info" => Level::Info,
                "warn" => Level::Warn,
                "error" => Level::Error,
                _ => Level::Warn,
            },
            Err(_) => Level::Warn,
        }
    })
}

fn should_log(level: Level) -> bool {
    level >= threshold()
}

fn timestamp() -> String {
    let now = OffsetDateTime::now_local().expect("local time unavailable");
    let fmt = format_description!("[year repr:last_two]/[month]/[day]|[hour]:[minute]:[second]");
    now.format(&fmt).unwrap()
}

pub fn debug(message: &str) {
    if !should_log(Level::Debug) {
        return;
    }

    println!("[DEBUG][{}] {}", timestamp(), message);
}

pub fn info(message: &str) {
    if !should_log(Level::Info) {
        return;
    }

    println!("[INFO][{}] {}", timestamp(), message);
}

pub fn warn(message: &str) {
    if !should_log(Level::Warn) {
        return;
    }

    println!("[WARN][{}] {}", timestamp(), message);
}

pub fn error(message: &str) {
    if !should_log(Level::Error) {
        return;
    }

    eprintln!("[ERROR][{}] {}", timestamp(), message);
}
