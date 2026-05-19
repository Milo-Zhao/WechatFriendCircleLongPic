import { invoke } from "@tauri-apps/api/core";
import type { Item } from "./store";

export interface ImageInfo { width: number; height: number; crop_loss: number; }
export interface ArrangeResult {
  ordered_urls: string[];
  thumbnail_url: string;
  padding_pixels: number;
  padding_fraction: number;
  crop_loss_fraction: number;
}

interface RustItem {
  url: string;
  is_thumbnail: boolean;
  custom_crop_origin: [number, number] | null;
}

function toRust(items: Item[]): RustItem[] {
  return items.map((it) => ({
    url: it.url,
    is_thumbnail: it.isThumbnail,
    custom_crop_origin: it.customCropOrigin,
  }));
}

export async function getImageInfo(path: string): Promise<ImageInfo> {
  return invoke("get_image_info", { path });
}

export async function composeToTemp(items: Item[], outputWidth: number): Promise<string> {
  return invoke("compose_to_temp", { items: toRust(items), outputWidth });
}

export async function saveComposed(items: Item[], outputWidth: number, outputPath: string): Promise<void> {
  return invoke("save_composed", { items: toRust(items), outputWidth, outputPath });
}

export async function autoArrange(
  items: Item[],
  outputWidth: number,
  cropWeight: number,
  fixedThumbnail: string | null,
): Promise<ArrangeResult> {
  return invoke("auto_arrange", {
    items: toRust(items),
    outputWidth,
    cropWeight,
    fixedThumbnail,
  });
}
