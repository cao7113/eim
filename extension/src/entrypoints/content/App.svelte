<script lang="ts">
  import type { DictionaryEntry, LookupError, LookupResponse } from '../../shared/dictionary';

  let root: HTMLElement;
  let visible = $state(false);
  let x = $state(0);
  let y = $state(0);
  let text = $state('');
  let entry = $state<DictionaryEntry | null>(null);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let requestId = 0;

  const maxTextLength = 500;

  function closePopup() {
    requestId += 1;
    visible = false;
    loading = false;
  }

  function positionPopup(rect: DOMRect) {
    const popupWidth = 344;
    x = Math.max(8, Math.min(rect.left, window.innerWidth - popupWidth - 8));
    y = rect.bottom + 8;

    if (y > window.innerHeight - 120) {
      y = Math.max(8, rect.top - 120);
    }
  }

  async function onMouseUp(e: MouseEvent) {
    if (e.composedPath().includes(root)) return;

    const sel = window.getSelection();
    const selected = sel?.toString().trim() ?? '';
    if (!selected || !sel || sel.rangeCount === 0) {
      closePopup();
      return;
    }

    const rect = sel.getRangeAt(0).getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0) {
      closePopup();
      return;
    }

    const currentRequestId = ++requestId;
    text = selected;
    positionPopup(rect);
    entry = null;
    error = null;
    visible = true;

    if (selected.length > maxTextLength) {
      error = '选中内容过长，请缩短后重试。';
      loading = false;
      return;
    }

    loading = true;

    try {
      const response = (await browser.runtime.sendMessage({
        type: 'lookup',
        text: selected,
      })) as LookupResponse;

      if (currentRequestId !== requestId) return;

      if (response.ok) {
        entry = response.entry;
      } else {
        error = errorMessage(response.error);
      }
    } catch (reason) {
      console.error('Unable to request dictionary lookup:', reason);
      if (currentRequestId === requestId) {
        error = '暂时无法连接词典服务。';
      }
    } finally {
      if (currentRequestId === requestId) {
        loading = false;
      }
    }
  }

  function onPointerDown(event: PointerEvent) {
    if (!event.composedPath().includes(root)) closePopup();
  }

  function onKeyDown(event: KeyboardEvent) {
    if (event.key === 'Escape' && visible) closePopup();
  }

  function errorMessage(reason: LookupError) {
    switch (reason) {
      case 'too_long':
        return '选中内容过长，请缩短后重试。';
      case 'unavailable':
        return '暂时无法连接词典服务。';
      case 'invalid_response':
      case 'failed':
        return '查询失败，请稍后重试。';
    }
  }
</script>

<svelte:document onpointerdown={onPointerDown} onmouseup={onMouseUp} onkeydown={onKeyDown} />
<svelte:window onscroll={closePopup} />

<div bind:this={root}>
  {#if visible}
    <section
      class="eim-card"
      style:left="{x}px"
      style:top="{y}px"
      role="status"
      aria-live="polite"
      aria-label="词典查询结果"
    >
      <header class="eim-header">
        <div class="eim-word">{text}</div>
        <button class="eim-close" type="button" aria-label="关闭" onclick={closePopup}>×</button>
      </header>

      {#if loading}
        <p class="eim-state">查询中…</p>
      {:else if error}
        <p class="eim-state eim-error">{error}</p>
      {:else if entry && entry.match === 'miss'}
        <p class="eim-state">词典暂无结果</p>
      {:else if entry}
        {#if entry.lemma && entry.lemma.toLowerCase() !== entry.text.toLowerCase()}
          <div class="eim-lemma">原型：{entry.lemma}</div>
        {/if}
        {#if entry.phonetic}
          <div class="eim-phonetic">{entry.phonetic}</div>
        {/if}
        {#if entry.senses.length > 0}
          <ul class="eim-senses">
            {#each entry.senses as sense, index (index)}
              <li>
                {#if sense.pos}<span class="eim-pos">{sense.pos}</span>{/if}
                {#if sense.domain}<span class="eim-domain">{sense.domain}</span>{/if}
                <span>{sense.zh}</span>
              </li>
            {/each}
          </ul>
        {:else}
          <p class="eim-state">词典暂无释义</p>
        {/if}
      {/if}
    </section>
  {/if}
</div>