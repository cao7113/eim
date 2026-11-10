<script lang="ts">
  let root: HTMLElement;
  let visible = $state(false);
  let x = $state(0);
  let y = $state(0);
  let text = $state('');
  let result = $state('');
  let loading = $state(false);

  async function onMouseUp(e: MouseEvent) {
    // 点在我们自己的卡片里，忽略
    if (e.composedPath().includes(root)) return;

    const sel = window.getSelection();
    const selected = sel?.toString().trim() ?? '';
    if (!selected || !sel || sel.rangeCount === 0) {
      visible = false;
      return;
    }

    const rect = sel.getRangeAt(0).getBoundingClientRect();
    text = selected;
    x = rect.left;
    y = rect.bottom + 8;
    result = '';
    visible = true;

    loading = true;
    try {
      const res = await browser.runtime.sendMessage({ type: 'translate', text: selected });
      if (text === selected) result = res.result; // 防止旧请求覆盖新选区
    } finally {
      loading = false;
    }
  }
</script>

<svelte:document onmouseup={onMouseUp} />

<div bind:this={root}>
  {#if visible}
    <div class="eim-card" style="left:{x}px; top:{y}px">
      <div class="eim-word">{text}</div>
      <div class="eim-result">{loading ? '翻译中…' : result}</div>
    </div>
  {/if}
</div>