import { writable, derived } from "svelte/store";

export interface Item {
  url: string;         // absolute fs path
  width: number;
  height: number;
  cropLoss: number;    // 0..1
  isThumbnail: boolean;
  customCropOrigin: [number, number] | null;
}

export const items = writable<Item[]>([]);
export const outputWidth = writable<number>(1080);
export const cropWeight = writable<number>(0.5);
export const userPickedThumbnail = writable<boolean>(false);
export const isWorking = writable<boolean>(false);
export const statusMessage = writable<string | null>(null);
export const previewPath = writable<string | null>(null);

export const hasThumbnail = derived(items, ($i) => $i.some((x) => x.isThumbnail));
