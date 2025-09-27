use time::{OffsetDateTime};


#[inline]
pub fn now_unix() -> i64 {
    OffsetDateTime::now_utc().unix_timestamp()
}