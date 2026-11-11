<script lang="ts">
  import { onMount } from 'svelte';
  import type {
    DictionaryEntry,
    ExtensionAuthResult,
    LookupError,
    LookupResponse,
    VocabEntryActionResult,
    VocabEntryStatus,
  } from '../../shared/dictionary';

  let root: HTMLElement;
  let lookupEnabled = $state(true);
  let visible = $state(false);
  let x = $state(0);
  let y = $state(0);
  let text = $state('');
  let entry = $state<DictionaryEntry | null>(null);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let vocabStatus = $state<VocabEntryStatus>({ status: 'checking' });
  let vocabBusy = $state(false);
  let noteExpanded = $state(false);
  let note = $state('');
  let vocabError = $state('');
  let requestId = 0;
  let vocabActionId = 0;

  const maxTextLength = 500;
  const maxNoteLength = 2000;

  onMount(() => {
    void browser.runtime.sendMessage({ type: 'get-lookup-setting' })
      .then((settings: { enabled: boolean }) => {
        lookupEnabled = settings.enabled;
      })
      .catch((reason: unknown) => {
        console.error('Unable to load lookup setting:', reason);
      });

    const onSettingsChanged = (message: unknown) => {
      if (
        typeof message === 'object' &&
        message !== null &&
        (message as Record<string, unknown>).type === 'lookup-setting-changed' &&
        typeof (message as Record<string, unknown>).enabled === 'boolean'
      ) {
        lookupEnabled = (message as { enabled: boolean }).enabled;
        if (!lookupEnabled) closePopup();
      }
    };

    browser.runtime.onMessage.addListener(onSettingsChanged);
    return () => browser.runtime.onMessage.removeListener(onSettingsChanged);
  });

  function closePopup() {
    requestId += 1;
    vocabActionId += 1;
    visible = false;
    loading = false;
    vocabBusy = false;
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
    if (!lookupEnabled) return;
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
    vocabStatus = { status: 'checking' };
    vocabError = '';
    note = '';
    noteExpanded = false;
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
        if (response.entry.match !== 'miss') {
          void refreshVocabStatus(response.entry, currentRequestId);
        }
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

  async function refreshVocabStatus(currentEntry: DictionaryEntry, currentRequestId = requestId) {
    vocabStatus = { status: 'checking' };

    try {
      const result = (await browser.runtime.sendMessage({
        type: 'get-vocab-entry-status',
        entry: currentEntry,
      })) as VocabEntryStatus;
      if (currentRequestId === requestId) vocabStatus = result;
    } catch (reason) {
      console.error('Unable to check saved vocabulary status:', reason);
      if (currentRequestId === requestId) vocabStatus = { status: 'offline' };
    }
  }

  async function connectToSave() {
    const currentRequestId = requestId;
    const currentActionId = ++vocabActionId;
    vocabBusy = true;
    vocabError = '';

    try {
      const result = (await browser.runtime.sendMessage({
        type: 'connect-extension-account',
      })) as ExtensionAuthResult;

      if (currentRequestId !== requestId || currentActionId !== vocabActionId) return;
      if (!result.ok) {
        vocabError =
          result.error === 'unavailable'
            ? '无法连接 Eim 服务，请稍后重试。'
            : '登录已取消或连接失败，请重试。';
        return;
      }

      if (entry) await refreshVocabStatus(entry, currentRequestId);
    } catch (reason) {
      console.error('Unable to connect account from vocabulary popup:', reason);
      if (currentRequestId === requestId && currentActionId === vocabActionId) {
        vocabError = '登录连接失败，请重试。';
      }
    } finally {
      if (currentActionId === vocabActionId) vocabBusy = false;
    }
  }

  async function saveVocabEntry() {
    if (!entry || entry.match === 'miss' || note.length > maxNoteLength || vocabBusy) return;

    const currentRequestId = requestId;
    const currentActionId = ++vocabActionId;
    vocabBusy = true;
    vocabError = '';
    const currentEntry = entry;
    const currentNote = note;

    try {
      const result = (await browser.runtime.sendMessage({
        type: 'save-vocab-entry',
        entry: currentEntry,
        note: currentNote,
      })) as VocabEntryActionResult;

      if (currentRequestId !== requestId || currentActionId !== vocabActionId) return;
      if (result.ok) {
        vocabStatus = {
          status: 'saved',
          insertedAt: result.insertedAt,
          learnUrl: result.learnUrl,
        };
      } else if (result.error === 'signed_out') {
        vocabStatus = { status: 'signed_out' };
        vocabError = '登录已过期，请重新连接账号。';
      } else if (result.error === 'unavailable') {
        vocabError = '暂时无法连接 Eim 服务，笔记已保留，请重试。';
      } else {
        vocabError = '收藏失败，笔记已保留，请重试。';
      }
    } catch (reason) {
      console.error('Unable to save vocabulary entry:', reason);
      if (currentRequestId === requestId && currentActionId === vocabActionId) {
        vocabError = '收藏失败，笔记已保留，请重试。';
      }
    } finally {
      if (currentActionId === vocabActionId) vocabBusy = false;
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
      case 'disabled':
        return '划词查词已暂停。';
      case 'unavailable':
        return '暂时无法连接词典服务。';
      case 'invalid_response':
      case 'failed':
        return '查询失败，请稍后重试。';
    }
  }

  function collectedDate(value: string) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return value;
    return new Intl.DateTimeFormat('zh-CN', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    }).format(date);
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

        <div class="eim-vocab">
          {#if vocabStatus.status === 'checking'}
            <p class="eim-state">检查收藏状态…</p>
          {:else if vocabStatus.status === 'saved'}
            <time class="eim-saved-date" role="status" datetime={vocabStatus.insertedAt}>
              已收录于 {collectedDate(vocabStatus.insertedAt)}
            </time>
            <a class="eim-study-link" href={vocabStatus.learnUrl} target="_blank" rel="noopener noreferrer">
              在学习中心查看 <span aria-hidden="true">↗</span>
            </a>
          {:else if vocabStatus.status === 'signed_out'}
            <button class="eim-action" type="button" disabled={vocabBusy} onclick={connectToSave}>
              {vocabBusy ? '连接中…' : '登录后收藏'}
            </button>
          {:else if vocabStatus.status === 'offline'}
            <button
              class="eim-action eim-secondary"
              type="button"
              disabled={vocabBusy}
              onclick={() => entry && refreshVocabStatus(entry)}
            >
              重试检查收藏
            </button>
          {:else}
            {#if !noteExpanded}
              <button
                class="eim-note-toggle"
                type="button"
                onclick={() => (noteExpanded = true)}
              >
                添加笔记（可选）
              </button>
            {:else}
              <label class="eim-note-label" for="eim-vocab-note">笔记（可选）</label>
              <textarea
                id="eim-vocab-note"
                class="eim-note"
                bind:value={note}
                maxlength={maxNoteLength}
                rows="2"
                placeholder="写下这个词在当前语境中的含义…"
              ></textarea>
              <div class="eim-note-count">{note.length}/{maxNoteLength}</div>
            {/if}
            <button class="eim-action" type="button" disabled={vocabBusy} onclick={saveVocabEntry}>
              {vocabBusy ? '收藏中…' : '收藏'}
            </button>
          {/if}
          {#if vocabError}<p class="eim-state eim-error" role="alert">{vocabError}</p>{/if}
        </div>
      {/if}
    </section>
  {/if}
</div>