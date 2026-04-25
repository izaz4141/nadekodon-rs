use time::{OffsetDateTime, macros::format_description};

pub fn debug(message: &str) {
    let now = OffsetDateTime::now_local().expect("local time unavailable");
    let fmt = format_description!("[year repr:last_two]/[month]/[day]|[hour]:[minute]:[second]");
    let ts = now.format(&fmt).unwrap();

    println!("[DEBUG][{}] {}", ts, message);
}

pub fn info(message: &str) {
    let now = OffsetDateTime::now_local().expect("local time unavailable");
    let fmt = format_description!("[year repr:last_two]/[month]/[day]|[hour]:[minute]:[second]");
    let ts = now.format(&fmt).unwrap();

    println!("[INFO][{}] {}", ts, message);
}

pub fn warn(message: &str) {
    let now = OffsetDateTime::now_local().expect("local time unavailable");
    let fmt = format_description!("[year repr:last_two]/[month]/[day]|[hour]:[minute]:[second]");
    let ts = now.format(&fmt).unwrap();

    println!("[WARN][{}] {}", ts, message);
}

pub fn error(message: &str) {
    let now = OffsetDateTime::now_local().expect("local time unavailable");
    let fmt = format_description!("[year repr:last_two]/[month]/[day]|[hour]:[minute]:[second]");
    let ts = now.format(&fmt).unwrap();

    eprintln!("[ERROR][{}] {}", ts, message);
}
