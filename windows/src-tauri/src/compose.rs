use crate::{open_image, AppError, ImageInput};
use image::{imageops::FilterType, GenericImage, GenericImageView, ImageBuffer, Rgba, RgbaImage};

/// Stitch the items vertically at `output_width`, place the designated
/// thumbnail as a centered W×W square, and pad the bottom (or top) with
/// white so that the thumbnail's vertical midpoint coincides with the
/// long picture's midpoint.
pub fn compose(items: &[ImageInput], output_width: u32) -> Result<RgbaImage, AppError> {
    if items.is_empty() {
        return Err(AppError::NoImages);
    }
    let thumb_idx = items
        .iter()
        .position(|it| it.is_thumbnail)
        .ok_or(AppError::NoThumbnail)?;

    let w = output_width.max(1);

    let mut tiles: Vec<RgbaImage> = Vec::with_capacity(items.len());
    let mut heights: Vec<u32> = Vec::with_capacity(items.len());

    for (i, item) in items.iter().enumerate() {
        let img = open_image(&item.url)?.to_rgba8();
        let (iw, ih) = img.dimensions();
        if i == thumb_idx {
            // Crop to a square (custom origin or center), then resize to w × w.
            let side = iw.min(ih);
            let (cx, cy) = if let Some([ox, oy]) = item.custom_crop_origin {
                let max_x = iw.saturating_sub(side);
                let max_y = ih.saturating_sub(side);
                let x = (ox.round().max(0.0) as u32).min(max_x);
                let y = (oy.round().max(0.0) as u32).min(max_y);
                (x, y)
            } else {
                ((iw - side) / 2, (ih - side) / 2)
            };
            let view = image::imageops::crop_imm(&img, cx, cy, side, side).to_image();
            let scaled = image::imageops::resize(&view, w, w, FilterType::Lanczos3);
            tiles.push(scaled);
            heights.push(w);
        } else {
            // Scale to width w preserving aspect.
            let h = (((ih as f64) / (iw as f64)) * (w as f64)).round().max(1.0) as u32;
            let scaled = image::imageops::resize(&img, w, h, FilterType::Lanczos3);
            tiles.push(scaled);
            heights.push(h);
        }
    }

    // Y position of each tile when stacked top→bottom.
    let mut positions: Vec<u32> = Vec::with_capacity(items.len());
    let mut y: u32 = 0;
    for &h in &heights {
        positions.push(y);
        y = y.saturating_add(h);
    }
    let stacked_height = y;
    let thumb_y = positions[thumb_idx];

    let top_space = thumb_y;
    let bottom_space = stacked_height.saturating_sub(thumb_y).saturating_sub(w);
    let (pad_top, pad_bot) = if top_space < bottom_space {
        (bottom_space - top_space, 0u32)
    } else {
        (0u32, top_space - bottom_space)
    };
    let total_height = stacked_height + pad_top + pad_bot;

    let mut out: RgbaImage =
        ImageBuffer::from_pixel(w, total_height, Rgba([255u8, 255, 255, 255]));

    for (i, tile) in tiles.iter().enumerate() {
        let dst_y = positions[i] + pad_top;
        // Copy tile into the destination; both have width == w by construction.
        out.copy_from(tile, 0, dst_y)
            .map_err(|e| AppError::Load(format!("paste failed at tile {i}: {e}")))?;
    }

    Ok(out)
}
