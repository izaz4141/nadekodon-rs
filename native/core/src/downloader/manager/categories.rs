use anyhow::Result;
use std::path::PathBuf;

use crate::utils::types::CategoryInfo;

use crate::downloader::manager::DownloadManager;

impl DownloadManager {
    pub async fn create_category(
        &self,
        name: String,
        save_path: Option<PathBuf>,
    ) -> Result<(), &'static str> {
        if name.is_empty() {
            return Err("Category name is empty");
        }
        if name.contains('|') || name.contains('/') {
            return Err("Invalid category name");
        }

        let mut categories = self.categories.write().await;
        if categories.contains_key(&name) {
            return Ok(());
        }

        categories.insert(name.clone(), CategoryInfo { name, save_path });

        if let Some(ctx) = self.context.upgrade() {
            let db = ctx.db().await;
            tokio::spawn(async move {
                db.save_categories().await;
            });
        }

        Ok(())
    }
}
