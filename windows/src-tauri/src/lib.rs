mod compose;
mod arrange;

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Item describing one input image as seen by the frontend.
/// `url` is an absolute filesystem path on Windows; we keep the name `url`
/// to match the Swift code's conventions and to be a stable IPC key.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageInput {
    pub url: String,
    #[serde(default)]
    pub is_thumbnail: bool,
    /// Top-left of the chosen square crop in original-pixel coords, top-left origin.
    /// `None` => center crop.
    #[serde(default)]
    pub custom_crop_origin: Option<[f64; 2]>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ImageInfo {
    pub width: u32,
    pub height: u32,
    pub crop_loss: f64,
}

#[derive(Debug, Clone, Serialize)]
pub struct ArrangeResult {
    pub ordered_urls: Vec<String>,
    pub thumbnail_url: String,
    pub padding_pixels: u32,
    pub padding_fraction: f64,
    pub crop_loss_fraction: f64,
}

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("no images provided")]
    NoImages,
    #[error("no thumbnail designated")]
    NoThumbnail,
    #[error("failed to load image: {0}")]
    Load(String),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("image: {0}")]
    Image(#[from] image::ImageError),
}

impl serde::Serialize for AppError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_string())
    }
}

// ---------- Tauri commands ----------

#[tauri::command]
fn get_image_info(path: String) -> Result<ImageInfo, AppError> {
    let dim = image::image_dimensions(&path).map_err(|e| AppError::Load(format!("{path}: {e}")))?;
    let (w, h) = dim;
    let mn = w.min(h) as f64;
    let mx = w.max(h) as f64;
    let crop_loss = if mx > 0.0 { 1.0 - mn / mx } else { 0.0 };
    Ok(ImageInfo { width: w, height: h, crop_loss })
}

/// Compose the long picture and write it to `output_path` as PNG.
#[tauri::command]
fn save_composed(
    items: Vec<ImageInput>,
    output_width: u32,
    output_path: String,
) -> Result<(), AppError> {
    let img = compose::compose(&items, output_width)?;
    img.save_with_format(&output_path, image::ImageFormat::Png)?;
    Ok(())
}

/// Compose into a temp PNG and return its path — the frontend then loads
/// it via the asset:// protocol for preview.
#[tauri::command]
fn compose_to_temp(items: Vec<ImageInput>, output_width: u32) -> Result<String, AppError> {
    let img = compose::compose(&items, output_width)?;
    let mut tmp = std::env::temp_dir();
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    tmp.push(format!("longpic-preview-{stamp}.png"));
    img.save_with_format(&tmp, image::ImageFormat::Png)?;
    Ok(tmp.to_string_lossy().to_string())
}

#[tauri::command]
fn auto_arrange(
    items: Vec<ImageInput>,
    output_width: u32,
    crop_weight: f64,
    fixed_thumbnail: Option<String>,
) -> Result<ArrangeResult, AppError> {
    arrange::recommend(&items, output_width, crop_weight, fixed_thumbnail.as_deref())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![
            get_image_info,
            save_composed,
            compose_to_temp,
            auto_arrange
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// Re-exports for the inner modules.
pub(crate) fn open_image(path: &str) -> Result<image::DynamicImage, AppError> {
    image::open(path).map_err(|e| AppError::Load(format!("{path}: {e}")))
}

pub(crate) fn _ensure_path(_: &PathBuf) {}
