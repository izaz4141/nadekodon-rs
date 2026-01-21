use reqwest;
use semver::Version;
use serde::Serialize;
use serde_json::{Value, json};
use tokio::process::Command;

#[derive(Debug, Clone, Serialize)]
pub struct VersionInfo {
    pub version: String,
    pub tag_name: String,
    pub release_notes: String,
    pub published_at: String,
    pub error: Option<String>,
}

pub async fn get_latest_release(
    client: &reqwest::Client,
    owner: &str,
    repo: &str,
) -> Result<Value, String> {
    let url = format!(
        "https://api.github.com/repos/{}/{}/releases/latest",
        owner, repo
    );
    let res = client.get(url).send().await.map_err(|e| e.to_string())?;
    let json: Value = res.json().await.map_err(|e| e.to_string())?;
    Ok(json)
}

pub async fn get_all_releases(
    client: &reqwest::Client,
    owner: &str,
    repo: &str,
) -> Result<Value, String> {
    let url = format!("https://api.github.com/repos/{}/{}/releases", owner, repo);
    let res = client.get(url).send().await.map_err(|e| e.to_string())?;
    let json: Value = res.json().await.map_err(|e| e.to_string())?;
    Ok(json)
}

pub async fn get_all_tags(
    client: &reqwest::Client,
    owner: &str,
    repo: &str,
) -> Result<Value, String> {
    let url = format!("https://api.github.com/repos/{}/{}/tags", owner, repo);
    let res = client.get(url).send().await.map_err(|e| e.to_string())?;
    let json: Value = res.json().await.map_err(|e| e.to_string())?;
    Ok(json)
}

fn extract_text_from_xml(xml: &str, tag: &str) -> Option<String> {
    let open_tag = format!("<{}>", tag);
    let close_tag = format!("</{}>", tag);
    if let Some(start) = xml.find(&open_tag)
        && let Some(end) = xml.find(&close_tag)
    {
        let content_start = start + open_tag.len();
        return Some(xml[content_start..end].to_string());
    }
    None
}

pub async fn get_latest_release_atom(
    client: &reqwest::Client,
    owner: &str,
    repo: &str,
) -> Result<Value, String> {
    let url = format!("https://github.com/{}/{}/releases.atom", owner, repo);
    let text = client
        .get(url)
        .send()
        .await
        .map_err(|e| e.to_string())?
        .text()
        .await
        .map_err(|e| e.to_string())?;

    if let Some(start) = text.find("<entry>")
        && let Some(end) = text.find("</entry>")
    {
        let entry = &text[start..end + 8];
        let tag_name = extract_text_from_xml(entry, "title").unwrap_or_default();
        let updated = extract_text_from_xml(entry, "updated").unwrap_or_default();
        let content = extract_text_from_xml(entry, "content").unwrap_or_default();

        return Ok(json!({
            "tag_name": tag_name,
            "body": content,
            "published_at": updated,
            "assets": []
        }));
    }
    Err("No entry found in Atom feed".to_string())
}

pub async fn get_all_releases_atom(
    client: &reqwest::Client,
    owner: &str,
    repo: &str,
) -> Result<Value, String> {
    let url = format!("https://github.com/{}/{}/releases.atom", owner, repo);
    let text = client
        .get(url)
        .send()
        .await
        .map_err(|e| e.to_string())?
        .text()
        .await
        .map_err(|e| e.to_string())?;

    let mut entries: Vec<Value> = Vec::new();
    let mut current = 0;

    while let Some(start) = text[current..].find("<entry>") {
        let start_pos = current + start;
        if let Some(end) = text[start_pos..].find("</entry>") {
            let end_pos = start_pos + end + 9;
            let entry = &text[start_pos..end_pos];

            let tag_name = extract_text_from_xml(entry, "title").unwrap_or_default();
            let updated = extract_text_from_xml(entry, "updated").unwrap_or_default();
            let content = extract_text_from_xml(entry, "content").unwrap_or_default();

            entries.push(json!({
                "tag_name": tag_name,
                "body": content,
                "published_at": updated,
                "assets": []
            }));
            current = end_pos;
        } else {
            break;
        }
    }

    Ok(json!(entries))
}

pub async fn get_all_tags_atom(
    client: &reqwest::Client,
    owner: &str,
    repo: &str,
) -> Result<Value, String> {
    let url = format!("https://github.com/{}/{}/tags.atom", owner, repo);
    let text = client
        .get(url)
        .send()
        .await
        .map_err(|e| e.to_string())?
        .text()
        .await
        .map_err(|e| e.to_string())?;

    let mut entries: Vec<Value> = Vec::new();
    let mut current = 0;

    while let Some(start) = text[current..].find("<entry>") {
        let start_pos = current + start;
        if let Some(end) = text[start_pos..].find("</entry>") {
            let end_pos = start_pos + end + 9;
            let entry = &text[start_pos..end_pos];

            let tag_name = extract_text_from_xml(entry, "title").unwrap_or_default();
            let updated = extract_text_from_xml(entry, "updated").unwrap_or_default();

            entries.push(json!({
                "tag_name": tag_name,
                "body": "",
                "published_at": updated,
                "assets": []
            }));
            current = end_pos;
        } else {
            break;
        }
    }

    Ok(json!(entries))
}

fn parse_lenient(version_str: &str) -> Result<Version, semver::Error> {
    let first_digit_idx = version_str.find(|c: char| c.is_ascii_digit());

    match first_digit_idx {
        Some(idx) => {
            let cleaned = &version_str[idx..];
            Version::parse(cleaned)
        }
        None => Version::parse(version_str),
    }
}

pub fn parse_pubspec_version(content: &str) -> (Option<String>, Option<String>) {
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("version:") {
            let version_part = trimmed.trim_start_matches("version:").trim();
            let parts: Vec<&str> = version_part.split('+').collect();
            let version = Some(parts[0].to_string());
            let build_number = if parts.len() > 1 {
                Some(parts[1].to_string())
            } else {
                None
            };
            return (version, build_number);
        }
    }
    (None, None)
}

async fn fetch_pubspec_version(
    client: &reqwest::Client,
    assets: &Value,
) -> (Option<String>, Option<String>) {
    if let Some(assets_arr) = assets.as_array() {
        for asset in assets_arr {
            if asset["name"].as_str() == Some("pubspec.yaml")
                && let Some(browser_url) = asset["browser_download_url"].as_str()
                && let Ok(resp) = client.get(browser_url).send().await
                && let Ok(text) = resp.text().await
            {
                return parse_pubspec_version(&text);
            }
        }
    }
    (None, None)
}

pub async fn get_latest_version(
    client: &reqwest::Client,
    owner: &str,
    repo: &str,
    check_nightly: bool,
    use_atom: bool,
) -> Result<VersionInfo, String> {
    if check_nightly {
        let releases_result = if use_atom {
            get_all_releases_atom(client, owner, repo).await
        } else {
            get_all_releases(client, owner, repo).await
        };

        let releases = releases_result.unwrap_or_else(|_| json!([]));
        let releases_arr = releases.as_array().map(|v| v.as_slice()).unwrap_or(&[]);

        let items: Vec<Value> = if releases_arr.is_empty() {
            let tags_result = if use_atom {
                get_all_tags_atom(client, owner, repo).await
            } else {
                get_all_tags(client, owner, repo).await
            };

            let tags = tags_result.unwrap_or_else(|_| json!([]));
            let tags_arr = tags.as_array().map(|v| v.as_slice()).unwrap_or(&[]);
            tags_arr
                .iter()
                .map(|t| {
                    json!({
                        "tag_name": t["tag_name"].clone(),
                        "body": "",
                        "published_at": t["published_at"].clone(),
                        "assets": []
                    })
                })
                .collect()
        } else {
            releases_arr.to_vec()
        };

        let mut latest_info: Option<VersionInfo> = None;
        let mut latest_version: Option<Version> = None;

        for item in items {
            let tag_name = item["tag_name"].as_str().unwrap_or_default().to_string();
            let assets = item["assets"].clone();
            let (pubspec_version, build_number) = if use_atom {
                (None, None)
            } else {
                fetch_pubspec_version(client, &assets).await
            };

            let version_string = if let Some(pub_ver) = &pubspec_version {
                if let Some(build) = &build_number {
                    format!("{}+{}", pub_ver, build)
                } else {
                    pub_ver.clone()
                }
            } else {
                tag_name.clone()
            };

            match parse_lenient(&version_string) {
                Ok(version) => {
                    if latest_version
                        .as_ref()
                        .map(|v| custom_compare(&version, v))
                        .unwrap_or(true)
                    {
                        latest_version = Some(version);
                        latest_info = Some(VersionInfo {
                            version: version_string,
                            tag_name,
                            release_notes: item["body"].as_str().unwrap_or("").to_string(),
                            published_at: item["published_at"].as_str().unwrap_or("").to_string(),
                            error: None,
                        });
                    }
                }
                Err(_) => continue,
            }
        }
        latest_info.ok_or("No release found".to_string())
    } else {
        let json_result = if use_atom {
            get_latest_release_atom(client, owner, repo).await
        } else {
            get_latest_release(client, owner, repo).await
        };

        let json = json_result?;
        let tag_name = json["tag_name"].as_str().ok_or("No tag_name")?.to_string();

        let (pubspec_version, build_number) = if use_atom {
            (None, None)
        } else {
            let assets = json["assets"].clone();
            fetch_pubspec_version(client, &assets).await
        };

        let version_string = match (&pubspec_version, &build_number) {
            (Some(pub_ver), Some(build)) => format!("{}+{}", pub_ver, build),
            (Some(pub_ver), None) => pub_ver.clone(),
            (None, None) => tag_name.clone(),
            (None, Some(_)) => tag_name.clone(),
        };

        Ok(VersionInfo {
            version: version_string,
            tag_name,
            release_notes: json["body"].as_str().unwrap_or("").to_string(),
            published_at: json["published_at"].as_str().unwrap_or("").to_string(),
            error: None,
        })
    }
}

pub async fn get_local_version(app: &str) -> Result<String, String> {
    let varg = if app == "ffmpeg" {
        "-version"
    } else {
        "--version"
    };
    let output = Command::new(app)
        .arg(varg)
        .output()
        .await
        .map_err(|e| e.to_string())?;

    let stdout = String::from_utf8_lossy(&output.stdout);

    for word in stdout.split_whitespace() {
        if word.contains('.') {
            let version = word.trim_end_matches(',').trim();
            return Ok(version.to_string());
        }
    }
    Err(format!("Could not parse {} version", app))
}

pub fn compare_versions(versions: &[String]) -> Option<String> {
    if versions.is_empty() {
        return None;
    }

    let mut latest: Option<Version> = None;
    let mut latest_str: Option<String> = None;

    for v in versions {
        match parse_lenient(v) {
            Ok(parsed) => {
                if latest
                    .as_ref()
                    .map(|p| custom_compare(&parsed, p))
                    .unwrap_or(true)
                {
                    latest = Some(parsed);
                    latest_str = Some(v.clone());
                }
            }
            Err(_) => continue,
        }
    }

    latest_str
}

fn custom_compare(current: &Version, best: &Version) -> bool {
    if current.major != best.major || current.minor != best.minor || current.patch != best.patch {
        return current > best;
    }
    current.build > best.build
}
