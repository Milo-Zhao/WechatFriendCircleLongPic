<script lang="ts">
  import { convertFileSrc } from "@tauri-apps/api/core";
  import { onMount } from "svelte";
  import type { Item } from "./store";
  import { items } from "./store";

  export let item: Item;
  export let onClose: () => void;

  const side = Math.min(item.width, item.height);
  let origin: [number, number] = item.customCropOrigin ?? [
    Math.floor((item.width - side) / 2),
    Math.floor((item.height - side) / 2),
  ];

  let containerEl: HTMLDivElement;
  let containerSize = { w: 1, h: 1 };

  $: scale = Math.min(containerSize.w / item.width, containerSize.h / item.height);
  $: displayedW = item.width * scale;
  $: displayedH = item.height * scale;
  $: displayedSide = side * scale;
  $: offsetX = (containerSize.w - displayedW) / 2;
  $: offsetY = (containerSize.h - displayedH) / 2;

  onMount(() => {
    const ro = new ResizeObserver(() => {
      const r = containerEl.getBoundingClientRect();
      containerSize = { w: r.width, h: r.height };
    });
    ro.observe(containerEl);
    return () => ro.disconnect();
  });

  function clampOrigin(x: number, y: number): [number, number] {
    const maxX = item.width - side;
    const maxY = item.height - side;
    return [
      Math.max(0, Math.min(maxX, x)),
      Math.max(0, Math.min(maxY, y)),
    ];
  }

  let dragging = false;
  function pointerDown(e: PointerEvent) {
    dragging = true;
    (e.target as Element).setPointerCapture(e.pointerId);
    pointerMove(e);
  }
  function pointerMove(e: PointerEvent) {
    if (!dragging) return;
    const rect = containerEl.getBoundingClientRect();
    const localX = (e.clientX - rect.left - offsetX) / scale;
    const localY = (e.clientY - rect.top - offsetY) / scale;
    origin = clampOrigin(localX - side / 2, localY - side / 2);
  }
  function pointerUp() { dragging = false; }

  function center() {
    origin = clampOrigin(
      (item.width - side) / 2,
      (item.height - side) / 2,
    );
  }

  function done() {
    items.update(($i) =>
      $i.map((it) =>
        it.url === item.url ? { ...it, customCropOrigin: origin } : it,
      ),
    );
    onClose();
  }

  function clearCustom() {
    items.update(($i) =>
      $i.map((it) =>
        it.url === item.url ? { ...it, customCropOrigin: null } : it,
      ),
    );
    onClose();
  }
</script>

<div class="backdrop" on:click|self={onClose}>
  <div class="sheet">
    <div class="header">
      <strong>Choose Thumbnail Crop</strong>
      <span class="muted">Drag to position the {side} × {side} square</span>
    </div>

    <div
      class="canvas"
      bind:this={containerEl}
      on:pointerdown={pointerDown}
      on:pointermove={pointerMove}
      on:pointerup={pointerUp}
      on:pointercancel={pointerUp}
    >
      <img
        src={convertFileSrc(item.url)}
        alt=""
        style="left:{offsetX}px;top:{offsetY}px;width:{displayedW}px;height:{displayedH}px"
      />
      <div
        class="overlay"
        style="left:{offsetX}px;top:{offsetY}px;width:{displayedW}px;height:{displayedH}px;
               --cx:{origin[0] * scale}px; --cy:{origin[1] * scale}px; --cs:{displayedSide}px"
      ></div>
      <div
        class="cropbox"
        style="left:{offsetX + origin[0] * scale}px;top:{offsetY + origin[1] * scale}px;
               width:{displayedSide}px;height:{displayedSide}px"
      ></div>
    </div>

    <div class="footer row">
      <button on:click={center}>Center</button>
      <button on:click={clearCustom}>Clear Custom</button>
      <span style="flex:1"></span>
      <button on:click={onClose}>Cancel</button>
      <button class="primary" on:click={done}>Done</button>
    </div>
  </div>
</div>

<style>
  .backdrop {
    position: fixed; inset: 0;
    background: rgba(0, 0, 0, 0.45);
    display: flex; align-items: center; justify-content: center;
    z-index: 100;
  }
  .sheet {
    background: var(--panel);
    border-radius: 10px;
    width: min(720px, 92vw);
    height: min(640px, 90vh);
    display: flex; flex-direction: column;
    padding: 14px;
    gap: 12px;
    box-shadow: 0 12px 32px rgba(0, 0, 0, 0.35);
  }
  .header { display: flex; align-items: baseline; justify-content: space-between; }
  .canvas {
    position: relative;
    flex: 1;
    background: rgba(127, 127, 127, 0.08);
    border-radius: 8px;
    overflow: hidden;
    touch-action: none;
  }
  .canvas img {
    position: absolute;
    pointer-events: none;
    user-select: none;
    -webkit-user-drag: none;
  }
  .overlay {
    position: absolute;
    background: rgba(0, 0, 0, 0.45);
    pointer-events: none;
    -webkit-mask:
      linear-gradient(#fff, #fff),
      linear-gradient(#fff, #fff);
    -webkit-mask-clip: content-box, padding-box;
    -webkit-mask-composite: xor;
    mask:
      linear-gradient(#fff, #fff) content-box,
      linear-gradient(#fff, #fff);
    mask-composite: exclude;
    clip-path: polygon(
      0 0, 100% 0, 100% 100%, 0 100%, 0 0,
      var(--cx) var(--cy),
      var(--cx) calc(var(--cy) + var(--cs)),
      calc(var(--cx) + var(--cs)) calc(var(--cy) + var(--cs)),
      calc(var(--cx) + var(--cs)) var(--cy),
      var(--cx) var(--cy)
    );
  }
  .cropbox {
    position: absolute;
    border: 2px solid #fff;
    box-sizing: border-box;
    pointer-events: none;
  }
  .footer { gap: 6px; }
</style>
