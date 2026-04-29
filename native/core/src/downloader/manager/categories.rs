use anyhow::Result;
use std::path::{Component, PathBuf};

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
            drop(categories);
            return Ok(());
        }

        if let Some(path) = &save_path {
            if path.components().any(|c| matches!(c, Component::ParentDir)) {
                return Err("Path traversal is not allowed in save_path");
            }
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

    pub async fn list_categories(&self) -> Vec<CategoryInfo> {
        let categories = self.categories.read().await.clone();
        categories.values().cloned().collect()
    }

    pub async fn update_categories(
        &self,
        categories: Vec<CategoryInfo>,
    ) -> Result<(), &'static str> {
        for cat in &categories {
            if cat.name.is_empty() {
                return Err("Category name is empty");
            }
            if cat.name.contains('|') || cat.name.contains('/') {
                return Err("Invalid category name");
            }
        }

        let mut map = self.categories.write().await;
        map.clear();
        for cat in categories {
            if let Some(path) = &cat.save_path {
                if path.components().any(|c| matches!(c, Component::ParentDir)) {
                    return Err("Path traversal is not allowed in save_path");
                }
            }
            map.insert(cat.name.clone(), cat);
        }

        if let Some(ctx) = self.context.upgrade() {
            let db = ctx.db().await;
            tokio::spawn(async move {
                db.save_categories().await;
            });
        }

        Ok(())
    }
}
