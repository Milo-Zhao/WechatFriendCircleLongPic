use crate::{AppError, ArrangeResult, ImageInput};

/// Same algorithm as the Swift AutoArrange:
///   * For every candidate thumbnail, run a boolean subset-sum DP on the
///     scaled heights of the other items, restricted to sums where
///     2 * s >= S so that any required padding lands at the BOTTOM.
///   * Score = (1 - cropWeight) * paddingFraction + cropWeight * cropLossFraction.
///   * The candidate with the smallest score wins.
pub fn recommend(
    items: &[ImageInput],
    output_width: u32,
    crop_weight: f64,
    fixed_thumbnail: Option<&str>,
) -> Result<ArrangeResult, AppError> {
    if items.is_empty() {
        return Err(AppError::NoImages);
    }
    let w = output_width.max(1) as i64;

    struct Entry {
        url: String,
        h: i64,
        crop_loss: f64,
    }

    let mut entries: Vec<Entry> = Vec::with_capacity(items.len());
    for it in items {
        let (iw, ih) = image::image_dimensions(&it.url)
            .map_err(|e| AppError::Load(format!("{}: {e}", it.url)))?;
        let h = (((ih as f64) / (iw as f64)) * (w as f64)).round().max(1.0) as i64;
        let mn = iw.min(ih) as f64;
        let mx = iw.max(ih) as f64;
        let crop_loss = if mx > 0.0 { 1.0 - mn / mx } else { 0.0 };
        entries.push(Entry { url: it.url.clone(), h, crop_loss });
    }

    if entries.len() == 1 {
        let e = &entries[0];
        return Ok(ArrangeResult {
            ordered_urls: vec![e.url.clone()],
            thumbnail_url: e.url.clone(),
            padding_pixels: 0,
            padding_fraction: 0.0,
            crop_loss_fraction: e.crop_loss,
        });
    }

    let alpha = crop_weight.clamp(0.0, 1.0);

    let candidate_range: Vec<usize> = if let Some(fixed) = fixed_thumbnail {
        match entries.iter().position(|e| e.url == fixed) {
            Some(i) => vec![i],
            None => (0..entries.len()).collect(),
        }
    } else {
        (0..entries.len()).collect()
    };

    let mut best: Option<(f64, usize, Vec<bool>, i64, f64, f64)> = None;

    for &t in &candidate_range {
        let mut others_idx: Vec<usize> = Vec::with_capacity(entries.len() - 1);
        let mut others_h: Vec<i64> = Vec::with_capacity(entries.len() - 1);
        for j in 0..entries.len() {
            if j == t {
                continue;
            }
            others_idx.push(j);
            others_h.push(entries[j].h);
        }
        let s_total: i64 = others_h.iter().sum();
        let cap = s_total as usize;
        let n = others_h.len();

        let mut reachable = vec![false; cap + 1];
        reachable[0] = true;
        let mut chosen = vec![false; n * (cap + 1)];

        for (k, &h) in others_h.iter().enumerate() {
            if (h as usize) > cap {
                continue;
            }
            let h_us = h as usize;
            let mut s = cap;
            while s >= h_us {
                if !reachable[s] && reachable[s - h_us] {
                    reachable[s] = true;
                    chosen[k * (cap + 1) + s] = true;
                }
                s -= 1;
            }
        }

        // Best reachable s with 2s >= S (padding at bottom).
        let mut best_sum: i64 = s_total;
        let mut best_delta: i64 = i64::MAX;
        for s in 0..=cap {
            if !reachable[s] {
                continue;
            }
            let s_i = s as i64;
            if 2 * s_i < s_total {
                continue;
            }
            let d = 2 * s_i - s_total;
            if d < best_delta {
                best_delta = d;
                best_sum = s_i;
            }
        }

        let padding = best_delta.max(0);
        let composed = s_total + w + padding;
        let pad_frac = if composed > 0 {
            padding as f64 / composed as f64
        } else {
            0.0
        };
        let crop_loss = entries[t].crop_loss;
        let score = (1.0 - alpha) * pad_frac + alpha * crop_loss;

        let improves = match &best {
            None => true,
            Some((bs, ..)) => score < *bs,
        };
        if improves {
            // Reconstruct one subset summing to best_sum.
            let mut above = vec![false; entries.len()];
            let mut s = best_sum as usize;
            let mut k = n as isize - 1;
            while k >= 0 && s > 0 {
                let ku = k as usize;
                if chosen[ku * (cap + 1) + s] {
                    above[others_idx[ku]] = true;
                    s -= others_h[ku] as usize;
                }
                k -= 1;
            }
            best = Some((score, t, above, padding, pad_frac, crop_loss));
        }
    }

    let (_, t, above, padding, pad_frac, crop_loss) =
        best.ok_or(AppError::NoImages)?;

    let mut above_urls: Vec<String> = Vec::new();
    let mut below_urls: Vec<String> = Vec::new();
    for j in 0..entries.len() {
        if j == t {
            continue;
        }
        if above[j] {
            above_urls.push(entries[j].url.clone());
        } else {
            below_urls.push(entries[j].url.clone());
        }
    }
    let thumb_url = entries[t].url.clone();
    let mut ordered = above_urls;
    ordered.push(thumb_url.clone());
    ordered.extend(below_urls);

    Ok(ArrangeResult {
        ordered_urls: ordered,
        thumbnail_url: thumb_url,
        padding_pixels: padding as u32,
        padding_fraction: pad_frac,
        crop_loss_fraction: crop_loss,
    })
}
