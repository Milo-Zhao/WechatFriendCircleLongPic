<script lang="ts">
  import { convertFileSrc } from "@tauri-apps/api/core";
  import type { Item } from "./store";
  import { items, userPickedThumbnail } from "./store";

  export let item: Item;
  export let index: number;
  export let onCrop: (item: Item) => void;
  export let onDragStart: (index: number) => void;
  export let onDragOver: (index: number, event: DragEvent) => void;
  export let onDrop: (index: number) => void;
  export let onRemove: (index: number) => void;

  $: previewUrl = convertFileSrc(item.url);
  $: filename = item.url.split(/[\\/]/).pop() ?? item.url;
  $: cropLossPct = Math.round(item.cropLoss * 100);
  $: isNonSquare = item.width !== item.height;

  function toggleStar() {
    items.update((list) =>
      list.map((it) => {
        if (it.url === item.url) {
          const next = !it.isThumbnail;
          return { ...it, isThumbnail: next };
        }
        // Star is exclusive: clear others when turning one on.
        if (!item.isThumbnail) return { ...it, isThumbnail: false };
        return it;
      }),
    );
    if (item.isThumbnail) {
      userPickedThumbnail.set(false);
    } else {
      userPickedThumbnail.set(true);
    }
  }
</script>

<div
  class="image-row"
  draggable="true"
  on:dragstart={() => onDragStart(index)}
  on:dragover|preventDefault={(e) => onDragOver(index, e)}
  on:drop|preventDefault={() => onDrop(index)}
>
  <button class="star" on:click={toggleStar} title="Use as WeChat thumbnail">
    {item.isThumbnail ? "★" : "☆"}
  </button>

  <img class="thumb" src={previewUrl} alt="" loading="lazy" />

  <div class="meta col">
    <div class="filename">{filename}</div>
    <div class="muted">{item.width} × {item.height}</div>
    {#if item.isThumbnail}
      <div class="muted">
        Thumbnail · crop {cropLossPct}%
        {#if item.customCropOrigin}
          <span class="custom">(custom)</span>
        {/if}
      </div>
    {/if}
  </div>

  <div class="actions row">
    {#if item.isThumbnail && isNonSquare}
      <button on:click={() => onCrop(item)} title="Choose crop region">Crop…</button>
    {/if}
    <button on:click={() => onRemove(index)} title="Remove">✕</button>
  </div>
</div>

<style>
  .image-row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 10px;
    border-bottom: 1px solid var(--border);
    background: var(--panel);
    cursor: grab;
  }
  .image-row:active { cursor: grabbing; }
  .star {
    border: none;
    background: transparent;
    font-size: 20px;
    line-height: 1;
    color: var(--star);
    padding: 0 4px;
  }
  .star:hover { background: transparent; }
  .thumb {
    width: 48px;
    height: 48px;
    object-fit: cover;
    border-radius: 4px;
    background: rgba(127, 127, 127, 0.1);
  }
  .meta { flex: 1; min-width: 0; }
  .filename {
    font-size: 13px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .custom { color: var(--accent); }
  .actions { gap: 4px; }
</style>
