<script lang="ts">
  import { convertFileSrc } from "@tauri-apps/api/core";
  import { open as openDialog, save as saveDialog } from "@tauri-apps/plugin-dialog";
  import ImageRow from "./lib/ImageRow.svelte";
  import CropPicker from "./lib/CropPicker.svelte";
  import {
    items, outputWidth, cropWeight, userPickedThumbnail,
    isWorking, statusMessage, previewPath, hasThumbnail,
    type Item,
  } from "./lib/store";
  import { getImageInfo, composeToTemp, saveComposed, autoArrange } from "./lib/api";

  let cropTarget: Item | null = null;
  let dragIndex: number | null = null;
  let previewVisible = true;

  async function addImages() {
    const picked = await openDialog({
      multiple: true,
      filters: [{
        name: "Images",
        extensions: ["png", "jpg", "jpeg", "webp", "bmp", "tiff", "tif", "gif"],
      }],
    });
    if (!picked) return;
    const paths = Array.isArray(picked) ? picked : [picked];
    const additions: Item[] = [];
    for (const p of paths) {
      try {
        const info = await getImageInfo(p);
        additions.push({
          url: p,
          width: info.width,
          height: info.height,
          cropLoss: info.crop_loss,
          isThumbnail: false,
          customCropOrigin: null,
        });
      } catch (e) {
        console.error("get_image_info failed", p, e);
      }
    }
    items.update(($i) => [...$i, ...additions]);
  }

  function dragStart(i: number) { dragIndex = i; }
  function dragOver(i: number, e: DragEvent) {
    e.preventDefault();
    if (dragIndex === null || dragIndex === i) return;
  }
  function drop(i: number) {
    if (dragIndex === null || dragIndex === i) { dragIndex = null; return; }
    items.update(($i) => {
      const next = $i.slice();
      const [moved] = next.splice(dragIndex!, 1);
      next.splice(i, 0, moved);
      return next;
    });
    dragIndex = null;
  }

  function remove(i: number) {
    items.update(($i) => {
      const next = $i.slice();
      const wasThumb = next[i].isThumbnail;
      next.splice(i, 1);
      if (wasThumb) userPickedThumbnail.set(false);
      return next;
    });
  }

  async function preview() {
    if ($items.length === 0 || !$hasThumbnail) return;
    isWorking.set(true);
    statusMessage.set(null);
    try {
      const path = await composeToTemp($items, $outputWidth);
      previewPath.set(path);
    } catch (e) {
      statusMessage.set(String(e));
    } finally {
      isWorking.set(false);
    }
  }

  async function exportSave() {
    if ($items.length === 0 || !$hasThumbnail) return;
    const target = await saveDialog({
      defaultPath: "wechat_long_pic.png",
      filters: [{ name: "PNG", extensions: ["png"] }],
    });
    if (!target) return;
    isWorking.set(true);
    statusMessage.set(null);
    try {
      await saveComposed($items, $outputWidth, target);
      statusMessage.set(`Saved to ${target}`);
    } catch (e) {
      statusMessage.set(String(e));
    } finally {
      isWorking.set(false);
    }
  }

  async function autoArrangeNow() {
    if ($items.length === 0) return;
    isWorking.set(true);
    statusMessage.set(null);
    const fixed = $userPickedThumbnail
      ? ($items.find((x) => x.isThumbnail)?.url ?? null)
      : null;
    try {
      const r = await autoArrange($items, $outputWidth, $cropWeight, fixed);
      const byUrl = new Map($items.map((x) => [x.url, x]));
      const reordered: Item[] = r.ordered_urls
        .map((u) => byUrl.get(u))
        .filter((x): x is Item => !!x)
        .map((x) => ({ ...x, isThumbnail: x.url === r.thumbnail_url }));
      items.set(reordered);
      const padPct = Math.round(r.padding_fraction * 100);
      const cropPct = Math.round(r.crop_loss_fraction * 100);
      const mode = fixed === null
        ? "picked thumbnail + order"
        : "kept your thumbnail, reordered";
      statusMessage.set(
        `Auto-arranged (${mode}) · padding ≈ ${r.padding_pixels} px (${padPct}%) · crop ≈ ${cropPct}%`,
      );
      await preview();
    } catch (e) {
      statusMessage.set(String(e));
    } finally {
      isWorking.set(false);
    }
  }
</script>

<div class="split">
  <aside class="left col">
    <div class="toolbar row">
      <button on:click={addImages}>＋ Add Images…</button>
      <span style="flex:1"></span>
      <span class="muted">Width</span>
      <input
        type="number"
        min="200"
        max="4096"
        bind:value={$outputWidth}
      />
      <span class="muted">px</span>
    </div>

    <div class="scroll list">
      {#each $items as item, i (item.url)}
        <ImageRow
          {item}
          index={i}
          onCrop={(it) => (cropTarget = it)}
          onDragStart={dragStart}
          onDragOver={dragOver}
          onDrop={drop}
          onRemove={remove}
        />
      {:else}
        <div class="empty">
          <div class="big">🖼️</div>
          <p>Add images, then either star one as the WeChat thumbnail<br />
            or hit <strong>Auto Arrange</strong> to let the app pick.</p>
        </div>
      {/each}
    </div>

    <div class="controls col">
      <div class="row weight">
        <span class="muted small">less padding</span>
        <input
          type="range" min="0" max="1" step="0.01"
          bind:value={$cropWeight}
        />
        <span class="muted small">less cropping</span>
      </div>
      <div class="row">
        <button
          on:click={autoArrangeNow}
          disabled={$items.length === 0 || $isWorking}
        >
          ✨ Auto Arrange
        </button>
        <button
          on:click={preview}
          disabled={$items.length === 0 || $isWorking || !$hasThumbnail}
          title={$hasThumbnail ? "" : "Star a thumbnail row, or run Auto Arrange"}
        >
          Preview
        </button>
        <span style="flex:1"></span>
        <button
          class="primary"
          on:click={exportSave}
          disabled={$items.length === 0 || $isWorking || !$hasThumbnail}
        >
          Export Long Pic…
        </button>
      </div>
      {#if $statusMessage}
        <div class="muted small">{$statusMessage}</div>
      {/if}
    </div>
  </aside>

  <main class="right">
    {#if $isWorking}
      <div class="placeholder">Working…</div>
    {:else if $previewPath && previewVisible}
      <div class="preview-wrap scroll">
        <div class="preview-inner">
          <img class="preview-img" src={convertFileSrc($previewPath)} alt="preview" />
          <div class="center-marker"></div>
        </div>
      </div>
    {:else}
      <div class="placeholder">
        <div class="big">📐</div>
        <p>Add images on the left and hit <strong>Preview</strong> or <strong>Auto Arrange</strong>.</p>
        <p class="muted small">A red dashed square will show what WeChat will crop as the thumbnail.</p>
      </div>
    {/if}
  </main>
</div>

{#if cropTarget}
  <CropPicker item={cropTarget} onClose={() => (cropTarget = null)} />
{/if}

<style>
  .split {
    display: flex;
    height: 100vh;
  }
  .left {
    width: 420px;
    border-right: 1px solid var(--border);
    background: var(--panel);
  }
  .right {
    flex: 1;
    display: flex;
    align-items: stretch;
    justify-content: stretch;
    background: var(--bg);
  }
  .toolbar {
    padding: 10px;
    border-bottom: 1px solid var(--border);
  }
  .list {
    flex: 1;
    min-height: 0;
    background: var(--bg);
  }
  .empty {
    padding: 40px 20px;
    text-align: center;
    color: var(--muted);
  }
  .big { font-size: 36px; margin-bottom: 6px; }
  .controls {
    padding: 10px;
    gap: 8px;
    border-top: 1px solid var(--border);
  }
  .weight { gap: 8px; }
  .weight input[type="range"] { flex: 1; }
  .small { font-size: 11px; }

  .preview-wrap {
    width: 100%;
    height: 100%;
    padding: 24px;
  }
  .preview-inner {
    position: relative;
    max-width: 480px;
    margin: 0 auto;
  }
  .preview-img {
    width: 100%;
    display: block;
    background: #fff;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
  }
  /* Center-square overlay — width == container width, vertically centered. */
  .preview-inner::before {
    /* Sized via JS would be nicer, but visually we approximate: the marker
       is rendered as a 100%-wide square pinned to the vertical center via
       padding-top trick is complex; use the .center-marker absolute div. */
    content: "";
  }
  .center-marker {
    position: absolute;
    left: 0; right: 0;
    aspect-ratio: 1 / 1;
    top: 50%;
    transform: translateY(-50%);
    border: 2px dashed rgba(210, 54, 54, 0.85);
    pointer-events: none;
  }
  .placeholder {
    margin: auto;
    text-align: center;
    color: var(--muted);
    padding: 40px;
  }
</style>
