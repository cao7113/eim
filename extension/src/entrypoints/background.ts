import type {
  DictionaryConnection,
  DictionaryEntry,
  ExtensionActionResult,
  ExtensionAccount,
  ExtensionAuthResult,
  LookupResponse,
  VocabEntryActionResult,
  VocabEntryStatus,
} from '../shared/dictionary';
import {
  defaultProductionEnvironment,
  developmentEnvironments,
  productionEnvironments,
  type Environment,
} from '../shared/environments';

const trustedStorageReady = browser.storage.local
  .setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' })
  .then(async () => {
    await browser.storage.local.remove([
      'extensionToken',
      'extensionKeyId',
      'extensionEmail',
      'extensionTokenExpiresAt',
    ]);
    return true;
  })
  .catch((error: unknown) => {
    console.error('Unable to restrict extension storage access:', error);
    return false;
  });

export default defineBackground(() => {
  browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (isMessage(message, 'get-environment')) {
      getEnvironment().then(
        (environment) => sendResponse({ environment }),
        (error: unknown) => {
          console.error('Unable to load service environment:', error);
          sendResponse({ error: 'unavailable' });
        },
      );
      return true;
    }

    if (isMessage(message, 'set-environment')) {
      const id = (message as Record<string, unknown>).id;
      const environments = import.meta.env.DEV ? developmentEnvironments : productionEnvironments;
      const environment = environments.find((candidate) => candidate.id === id);
      if (
        !environment ||
        sender.tab ||
        !sender.url?.startsWith(browser.runtime.getURL('/'))
      ) {
        sendResponse({ ok: false });
        return;
      }

      setEnvironment(environment).then(
        (notified) => sendResponse(notified ? { ok: true } : { ok: false, error: 'notification_failed' }),
        (error: unknown) => {
          console.error('Unable to change service environment:', error);
          sendResponse({ ok: false });
        },
      );
      return true;
    }

    if (isMessage(message, 'get-lookup-setting')) {
      getLookupEnabled().then((enabled) => sendResponse({ enabled }));
      return true;
    }

    if (isSetLookupMessage(message)) {
      setLookupEnabled(message.enabled).then(
        () => sendResponse({ ok: true }),
        (error: unknown) => {
          console.error('Unable to save lookup setting:', error);
          sendResponse({ ok: false });
        },
      );
      return true;
    }

    if (isConnectionCheckMessage(message)) {
      withEnvironment(message, checkConnection).then(sendResponse, (error: unknown) => {
        console.error('Dictionary API connection check failed:', error);
        sendResponse({ status: 'offline' } satisfies DictionaryConnection);
      });
      return true;
    }

    if (isMessage(message, 'get-extension-account')) {
      withEnvironment(message, getExtensionAccount).then(sendResponse, (error: unknown) => {
        console.error('Unable to load extension account:', error);
        sendResponse({ status: 'offline' } satisfies ExtensionAccount);
      });
      return true;
    }

    if (isMessage(message, 'connect-extension-account')) {
      withEnvironment(message, connectExtensionAccount).then(sendResponse, (error: unknown) => {
        console.error('Unable to connect extension account:', error);
        sendResponse({ ok: false, error: 'failed' } satisfies ExtensionAuthResult);
      });
      return true;
    }

    if (isVocabStatusMessage(message)) {
      withEnvironment(message, (origin) => getVocabEntryStatus(origin, message.entry)).then(sendResponse, (error: unknown) => {
        console.error('Unable to check saved vocabulary status:', error);
        sendResponse({ status: 'offline' } satisfies VocabEntryStatus);
      });
      return true;
    }

    if (isSaveVocabMessage(message)) {
      withEnvironment(message, (origin) => saveVocabEntry(origin, message.entry, message.note)).then(sendResponse, (error: unknown) => {
        console.error('Unable to save vocabulary entry:', error);
        sendResponse({ ok: false, error: 'failed' } satisfies VocabEntryActionResult);
      });
      return true;
    }

    if (isMessage(message, 'disconnect-extension-account')) {
      withEnvironment(message, disconnectExtensionAccount).then(sendResponse, (error: unknown) => {
        console.error('Unable to disconnect extension account:', error);
        sendResponse({ ok: false, error: 'failed' } satisfies ExtensionActionResult);
      });
      return true;
    }

    if (!isLookupMessage(message)) return;

    withEnvironment(message, (origin) => lookup(origin, message.text)).then(sendResponse, (error: unknown) => {
      console.error('Dictionary lookup failed:', error);
      sendResponse({ ok: false, error: 'failed' } satisfies LookupResponse);
    });

    return true;
  });
});

const maxTextLength = 500;

async function withEnvironment<T>(
  message: object,
  operation: (origin: string) => Promise<T>,
): Promise<T> {
  const environment = await getEnvironment();
  if (
    'environmentId' in message &&
    message.environmentId !== environment.id
  ) throw new Error('Service environment changed');
  return operation(environment.origin);
}

async function getEnvironment(): Promise<Environment> {
  if (!(await trustedStorageReady)) throw new Error('Extension storage is unavailable');
  const { serviceEnvironment } = await browser.storage.local.get('serviceEnvironment');
  if (serviceEnvironment === undefined) {
    return import.meta.env.DEV ? developmentEnvironments[0] : defaultProductionEnvironment;
  }
  if (!import.meta.env.DEV && serviceEnvironment === 'development') {
    console.warn('Saved development environment is unavailable in production; using the default production environment');
    return defaultProductionEnvironment;
  }
  const environments = import.meta.env.DEV ? developmentEnvironments : productionEnvironments;
  const environment = environments.find((candidate) => candidate.id === serviceEnvironment);
  if (!environment) throw new Error('Invalid service environment');
  return environment;
}

async function setEnvironment(environment: Environment): Promise<boolean> {
  if (!(await trustedStorageReady)) throw new Error('Extension storage is unavailable');
  await browser.storage.local.set({ serviceEnvironment: environment.id });
  let tabs;
  try {
    tabs = await browser.tabs.query({});
  } catch (error) {
    console.error('Unable to notify tabs of the service environment change:', error);
    return false;
  }
  const notifications = Promise.all(
    tabs
      .filter((tab) => tab.id !== undefined)
      .map((tab) =>
        browser.tabs.sendMessage(tab.id!, { type: 'service-environment-changed' }).catch(() => undefined),
      ),
  );
  let timeout: ReturnType<typeof setTimeout> | undefined;
  const notified = await Promise.race([
    notifications.then(() => true),
    new Promise<false>((resolve) => {
      timeout = setTimeout(() => resolve(false), 1000);
    }),
  ]);
  clearTimeout(timeout);
  if (!notified) console.error('Timed out notifying tabs of the service environment change');
  return notified;
}

type Credentials = {
  token: string;
  keyId: string;
  email: string;
  expiresAt: string;
};

function credentialsKey(origin: string): string {
  return `extensionCredentials:${origin}`;
}

async function readCredentials(origin: string): Promise<Credentials | null> {
  if (!(await trustedStorageReady)) throw new Error('Extension storage is unavailable');
  const key = credentialsKey(origin);
  const value: unknown = (await browser.storage.local.get(key))[key];
  if (value === undefined) return null;
  if (
    typeof value !== 'object' || value === null ||
    !('token' in value) || typeof value.token !== 'string' ||
    !('keyId' in value) || typeof value.keyId !== 'string' ||
    !('email' in value) || typeof value.email !== 'string' ||
    !('expiresAt' in value) || typeof value.expiresAt !== 'string'
  ) throw new Error('Invalid extension credentials');
  return { token: value.token, keyId: value.keyId, email: value.email, expiresAt: value.expiresAt };
}

const credentialUpdates = new Map<string, Promise<void>>();

async function updateCredentials(origin: string, update: () => Promise<void>): Promise<void> {
  const previous = credentialUpdates.get(origin) ?? Promise.resolve();
  const current = previous.catch(() => undefined).then(update);
  credentialUpdates.set(origin, current);
  try {
    await current;
  } finally {
    if (credentialUpdates.get(origin) === current) credentialUpdates.delete(origin);
  }
}

function isConnectionCheckMessage(message: unknown): message is { type: 'check-api-connection' } {
  return isMessage(message, 'check-api-connection');
}

function isMessage<T extends string>(
  message: unknown,
  type: T,
): message is { type: T } {
  return typeof message === 'object' && message !== null &&
    (message as Record<string, unknown>).type === type;
}

function isSetLookupMessage(message: unknown): message is { type: 'set-lookup-setting'; enabled: boolean } {
  return isMessage(message, 'set-lookup-setting') &&
    typeof (message as Record<string, unknown>).enabled === 'boolean';
}

function isVocabStatusMessage(
  message: unknown,
): message is { type: 'get-vocab-entry-status'; entry: DictionaryEntry } {
  return isMessage(message, 'get-vocab-entry-status') &&
    isDictionaryEntry((message as Record<string, unknown>).entry);
}

function isSaveVocabMessage(
  message: unknown,
): message is { type: 'save-vocab-entry'; entry: DictionaryEntry; note: string } {
  return isMessage(message, 'save-vocab-entry') &&
    isDictionaryEntry((message as Record<string, unknown>).entry) &&
    typeof (message as Record<string, unknown>).note === 'string';
}

function isLookupMessage(message: unknown): message is { type: 'lookup'; text: string } {
  if (typeof message !== 'object' || message === null) return false;
  const candidate = message as Record<string, unknown>;
  return candidate.type === 'lookup' && typeof candidate.text === 'string';
}

async function lookup(apiBaseUrl: string, text: string): Promise<LookupResponse> {
  if (text.trim().length === 0) {
    return { ok: false, error: 'failed' };
  }

  if (text.length > maxTextLength) {
    return { ok: false, error: 'too_long' };
  }

  if (!(await getLookupEnabled())) return { ok: false, error: 'disabled' };

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

async function getLookupEnabled(): Promise<boolean> {
  if (!(await trustedStorageReady)) throw new Error('Extension storage is unavailable');
  const { lookupEnabled = true } = await browser.storage.local.get('lookupEnabled');
  return lookupEnabled !== false;
}

async function setLookupEnabled(enabled: boolean): Promise<void> {
  if (!(await trustedStorageReady)) throw new Error('Extension storage is unavailable');
  await browser.storage.local.set({ lookupEnabled: enabled });
  const tabs = await browser.tabs.query({});
  await Promise.all(
    tabs
      .filter((tab) => tab.id !== undefined)
      .map((tab) =>
        browser.tabs.sendMessage(tab.id!, { type: 'lookup-setting-changed', enabled }).catch(() => undefined),
      ),
  );
}

async function checkConnection(apiBaseUrl: string): Promise<DictionaryConnection> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3_000);

  try {
    const response = await fetch(new URL('/api/open_api', apiBaseUrl), {
      signal: controller.signal,
    });

    return { status: response.ok ? 'connected' : 'offline' };
  } catch (error) {
    if (!(error instanceof DOMException && error.name === 'AbortError')) {
      console.error('Unable to check dictionary API connection:', error);
    }
    return { status: 'offline' };
  } finally {
    clearTimeout(timeout);
  }
}

async function getExtensionAccount(apiBaseUrl: string): Promise<ExtensionAccount> {
  const credentials = await readCredentials(apiBaseUrl);
  if (!credentials) return { status: 'signed_out' };
  const cachedEmail = credentials.email;

  try {
    const response = await fetch(new URL('/api/extension/me', apiBaseUrl), {
      headers: { Authorization: `Bearer ${credentials.token}` },
      redirect: 'error',
      signal: AbortSignal.timeout(5_000),
    });

    if (response.status === 401) {
      await clearExtensionCredentials(apiBaseUrl, credentials.token);
      return { status: 'signed_out' };
    }

    if (!response.ok) return { status: 'offline', email: cachedEmail };

    const body: unknown = await response.json();
    if (!isAccountResponse(body)) return { status: 'offline', email: cachedEmail };
    return { status: 'signed_in', email: body.email };
  } catch (error) {
    console.error('Unable to verify extension account:', error);
    return { status: 'offline', email: cachedEmail };
  }
}

async function connectExtensionAccount(apiBaseUrl: string): Promise<ExtensionAuthResult> {
  if (!(await trustedStorageReady)) {
    return { ok: false, error: 'unavailable' };
  }

  const verifier = randomToken(32);
  const challenge = await createCodeChallenge(verifier);
  const state = randomToken(32);
  const redirectUri = browser.identity.getRedirectURL();
  const authorizationUrl = new URL('/extension/authorize', apiBaseUrl);
  authorizationUrl.searchParams.set('redirect_uri', redirectUri);
  authorizationUrl.searchParams.set('code_challenge', challenge);
  authorizationUrl.searchParams.set('state', state);

  const callbackUrl = await browser.identity.launchWebAuthFlow({
    url: authorizationUrl.toString(),
    interactive: true,
  });

  if (!callbackUrl) return { ok: false, error: 'failed' };

  const callback = new URL(callbackUrl);
  const expectedCallback = new URL(redirectUri);
  const params = new URLSearchParams(callback.hash.slice(1));
  const code = params.get('code');

  if (
    callback.origin !== expectedCallback.origin ||
    callback.pathname !== expectedCallback.pathname ||
    params.get('state') !== state ||
    !code
  ) {
    console.error('Extension authorization callback did not match the request');
    return { ok: false, error: 'failed' };
  }

  return exchangeAuthorizationCode(apiBaseUrl, code, verifier);
}

  async function getVocabEntryStatus(apiBaseUrl: string, entry: DictionaryEntry): Promise<VocabEntryStatus> {
    const credentials = await getExtensionCredentials(apiBaseUrl);
    if (credentials.status !== 'signed_in') return credentials;

    const termKey = normalizeTerm(entry.lemma || entry.text);
    const url = new URL('/api/vocab/entries', apiBaseUrl);
    url.searchParams.set('filter[term_key]', termKey);

    try {
      const response = await fetch(url, {
        headers: {
          Accept: 'application/vnd.api+json',
          Authorization: `Bearer ${credentials.token}`,
        },
        redirect: 'error',
        signal: AbortSignal.timeout(5_000),
      });

      if (response.status === 401) {
        await clearExtensionCredentials(apiBaseUrl, credentials.token);
        return { status: 'signed_out' };
      }

      if (!response.ok) {
        console.error('Vocab API returned an unsuccessful status:', response.status);
        return { status: 'offline' };
      }

      const body: unknown = await response.json();
      if (!isVocabIndexResponse(body)) {
        console.error('Vocab API returned an invalid response');
        return { status: 'offline' };
      }

      const savedEntry = body.data[0];
      return savedEntry
        ? {
            status: 'saved',
            insertedAt: savedEntry.attributes.inserted_at,
            learnUrl: vocabLearnUrl(savedEntry.id, apiBaseUrl),
          }
        : { status: 'not_saved' };
    } catch (error) {
      console.error('Unable to check saved vocabulary status:', error);
      return { status: 'offline' };
    }
  }

  async function saveVocabEntry(
    apiBaseUrl: string,
    entry: DictionaryEntry,
    note: string,
  ): Promise<VocabEntryActionResult> {
    const credentials = await getExtensionCredentials(apiBaseUrl);
    if (credentials.status === 'signed_out') return { ok: false, error: 'signed_out' };
    if (credentials.status === 'offline') return { ok: false, error: 'unavailable' };

    try {
      const response = await fetch(new URL('/api/vocab/entries', apiBaseUrl), {
        method: 'POST',
        headers: {
          Accept: 'application/vnd.api+json',
          'Content-Type': 'application/vnd.api+json',
          Authorization: `Bearer ${credentials.token}`,
        },
        redirect: 'error',
        body: JSON.stringify({
          data: {
            type: 'vocab-entry',
            attributes: {
              lookup_text: entry.text,
              lemma: entry.lemma,
              phonetic: entry.phonetic,
              dictionary_snapshot: entry,
              note: note.trim() || null,
            },
          },
        }),
        signal: AbortSignal.timeout(5_000),
      });

      if (response.status === 401) {
        await clearExtensionCredentials(apiBaseUrl, credentials.token);
        return { ok: false, error: 'signed_out' };
      }

      if (!response.ok) {
        console.error('Vocab API save returned an unsuccessful status:', response.status);
        return { ok: false, error: 'failed' };
      }

      const body: unknown = await response.json();
      if (!isVocabResourceResponse(body)) {
        console.error('Vocab API save returned an invalid response');
        return { ok: false, error: 'failed' };
      }

      return {
        ok: true,
        insertedAt: body.data.attributes.inserted_at,
        learnUrl: vocabLearnUrl(body.data.id, apiBaseUrl),
      };
    } catch (error) {
      console.error('Unable to save vocabulary entry:', error);
      return { ok: false, error: 'unavailable' };
    }
  }

  async function getExtensionCredentials(origin: string): Promise<
    | { status: 'signed_in'; token: string }
    | { status: 'signed_out' }
    | { status: 'offline' }
  > {
    const credentials = await readCredentials(origin);
    if (!credentials) return { status: 'signed_out' };
    return { status: 'signed_in', token: credentials.token };
  }

  function normalizeTerm(value: string): string {
    return value.normalize('NFKC').trim().toLowerCase();
  }

  function vocabLearnUrl(id: string, baseUrl: string): string {
    const url = new URL('/learn/vocab', baseUrl);
    url.searchParams.set('entry_id', id);
    return url.toString();
  }

  type VocabApiEntry = {
    id: string;
    attributes: { inserted_at: string };
  };

  function isVocabResourceResponse(value: unknown): value is { data: VocabApiEntry } {
    if (typeof value !== 'object' || value === null) return false;
    const data = (value as Record<string, unknown>).data;
    return isVocabApiEntry(data);
  }

  function isVocabApiEntry(value: unknown): value is VocabApiEntry {
    if (typeof value !== 'object' || value === null) return false;
    const entry = value as Record<string, unknown>;
    const attributes = entry.attributes;
    return typeof entry.id === 'string' &&
      typeof attributes === 'object' &&
      attributes !== null &&
      typeof (attributes as Record<string, unknown>).inserted_at === 'string';
  }

  function isVocabIndexResponse(value: unknown): value is { data: VocabApiEntry[] } {
    if (typeof value !== 'object' || value === null) return false;
    const data = (value as Record<string, unknown>).data;
    return Array.isArray(data) && data.every(isVocabApiEntry);
  }

  function randomToken(byteLength: number): string {
    const bytes = crypto.getRandomValues(new Uint8Array(byteLength));
    return btoa(String.fromCharCode(...bytes))
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll('=', '');
  }

  async function createCodeChallenge(verifier: string): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
    return btoa(String.fromCharCode(...new Uint8Array(digest)))
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll('=', '');
  }

  async function exchangeAuthorizationCode(
    apiBaseUrl: string,
    code: string,
    verifier: string,
  ): Promise<ExtensionAuthResult> {
    if (!(await trustedStorageReady)) {
      return { ok: false, error: 'unavailable' };
    }

  try {
    const response = await fetch(new URL('/api/extension/token', apiBaseUrl), {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({ code, code_verifier: verifier }),
      redirect: 'error',
      signal: AbortSignal.timeout(5_000),
    });

    if (!response.ok) {
      console.error('Extension authorization exchange failed:', response.status);
      return { ok: false, error: 'failed' };
    }

    const body: unknown = await response.json();
    if (!isTokenResponse(body)) return { ok: false, error: 'failed' };

    await updateCredentials(apiBaseUrl, () => browser.storage.local.set({
      [credentialsKey(apiBaseUrl)]: {
        token: body.token,
        keyId: body.key_id,
        email: body.user.email,
        expiresAt: body.expires_at,
      },
    }));

    return { ok: true, account: { status: 'signed_in', email: body.user.email } };
  } catch (error) {
    console.error('Unable to exchange extension authorization code:', error);
    return { ok: false, error: 'unavailable' };
  }
}

async function disconnectExtensionAccount(apiBaseUrl: string): Promise<ExtensionActionResult> {
  const credentials = await readCredentials(apiBaseUrl);
  if (!credentials) return { ok: true };

  try {
    const response = await fetch(new URL('/api/extension/session', apiBaseUrl), {
      method: 'DELETE',
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${credentials.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ key_id: credentials.keyId }),
      redirect: 'error',
      signal: AbortSignal.timeout(5_000),
    });

    if (!response.ok && response.status !== 401) {
      return { ok: false, error: 'failed' };
    }

    await clearExtensionCredentials(apiBaseUrl, credentials.token);
    return { ok: true };
  } catch (error) {
    console.error('Unable to revoke extension credentials:', error);
    return { ok: false, error: 'unavailable' };
  }
}

async function clearExtensionCredentials(origin: string, token: string): Promise<void> {
  await updateCredentials(origin, async () => {
    const credentials = await readCredentials(origin);
    if (credentials?.token === token) await browser.storage.local.remove(credentialsKey(origin));
  });
}

function isAccountResponse(value: unknown): value is { id: string; email: string } {
  if (typeof value !== 'object' || value === null) return false;
  const body = value as Record<string, unknown>;
  return typeof body.id === 'string' && typeof body.email === 'string';
}

function isTokenResponse(
  value: unknown,
): value is { token: string; key_id: string; expires_at: string; user: { id: string; email: string } } {
  if (typeof value !== 'object' || value === null) return false;
  const body = value as Record<string, unknown>;
  return (
    typeof body.token === 'string' &&
    typeof body.key_id === 'string' &&
    typeof body.expires_at === 'string' &&
    isAccountResponse(body.user)
  );
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