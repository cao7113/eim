import type { DictionaryEntry, LookupResponse } from '../shared/dictionary';

export default defineBackground(() => {
  browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!isLookupMessage(message)) return;

    lookup(message.text).then(sendResponse, (error: unknown) => {
      console.error('Dictionary lookup failed:', error);
      sendResponse({ ok: false, error: 'failed' } satisfies LookupResponse);
    });

    return true;
  });
});

const maxTextLength = 500;
const apiBaseUrl = import.meta.env.DEV ? 'http://localhost:4000' : null;

function isLookupMessage(message: unknown): message is { type: 'lookup'; text: string } {
  if (typeof message !== 'object' || message === null) return false;
  const candidate = message as Record<string, unknown>;
  return candidate.type === 'lookup' && typeof candidate.text === 'string';
}

async function lookup(text: string): Promise<LookupResponse> {
  if (text.trim().length === 0 || text.length > maxTextLength) {
    return { ok: false, error: 'too_long' };
  }

  if (!apiBaseUrl) {
    return { ok: false, error: 'unavailable' };
  }

  const url = new URL('/api/dict/lookup', apiBaseUrl);
  url.searchParams.set('text', text);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5_000);

  try {
    const response = await fetch(url, {
      headers: { Accept: 'application/vnd.api+json' },
      signal: controller.signal,
    });

    if (!response.ok) {
      console.error('Dictionary API returned an unsuccessful status:', response.status);
      return { ok: false, error: 'failed' };
    }

    const body: unknown = await response.json();
    if (!isDictionaryEntry(body)) {
      console.error('Dictionary API returned an invalid response');
      return { ok: false, error: 'invalid_response' };
    }

    return { ok: true, entry: body };
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      return { ok: false, error: 'unavailable' };
    }

    if (error instanceof SyntaxError) {
      console.error('Dictionary API returned invalid JSON:', error);
      return { ok: false, error: 'invalid_response' };
    }

    console.error('Unable to reach dictionary API:', error);
    return { ok: false, error: 'unavailable' };
  } finally {
    clearTimeout(timeout);
  }
}

function isDictionaryEntry(value: unknown): value is DictionaryEntry {
  if (typeof value !== 'object' || value === null) return false;
  const entry = value as Record<string, unknown>;

  return (
    typeof entry.text === 'string' &&
    typeof entry.kind === 'string' &&
    typeof entry.match === 'string' &&
    (typeof entry.lemma === 'string' || entry.lemma === null) &&
    (typeof entry.phonetic === 'string' || entry.phonetic === null) &&
    Array.isArray(entry.senses) &&
    entry.senses.every(
      (sense: unknown) =>
        typeof sense === 'object' &&
        sense !== null &&
        typeof (sense as Record<string, unknown>).zh === 'string' &&
        ((sense as Record<string, unknown>).pos === null ||
          typeof (sense as Record<string, unknown>).pos === 'string') &&
        ((sense as Record<string, unknown>).domain === null ||
          typeof (sense as Record<string, unknown>).domain === 'string'),
    )
  );
}