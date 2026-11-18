import { beforeAll, beforeEach, describe, expect, test } from 'bun:test';

const storage = {};
const sessionStorage = {};
const sentMessages = [];
let listener;
let authFlow;
let fetchHandler;
let tabQuery;
let tabSendMessage;
let legacyRemoved;

const popupSender = { url: 'chrome-extension://test/popup.html' };
const origins = {
  development: 'http://localhost:4003',
  'local-production': 'https://eim.s',
  production: 'https://eim.fly.dev',
};
const authxOrigins = {
  development: 'http://localhost:4000',
};
const extensionClientId = '00000000-0000-7000-8000-000000000004';

function credentials(token) {
  return { token, keyId: `key-${token}`, email: `${token}@example.test`, expiresAt: '2030-01-01' };
}

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

function send(message, sender = popupSender) {
  return new Promise((resolve) => {
    const async = listener(message, sender, resolve);
    if (async !== true && async !== undefined) throw new Error('Unexpected message handler result');
  });
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

beforeAll(async () => {
  Bun.env.DEV = 'true';
  storage.extensionToken = 'legacy';
  globalThis.browser = {
    storage: {
      local: {
        setAccessLevel: async () => {},
        get: async (keys) => Object.fromEntries(
          (Array.isArray(keys) ? keys : [keys]).map((key) => [key, storage[key]]),
        ),
        set: async (values) => Object.assign(storage, values),
        remove: async (keys) => {
          for (const key of Array.isArray(keys) ? keys : [keys]) delete storage[key];
        },
      },
      session: {
        get: async (keys) => Object.fromEntries(
          (Array.isArray(keys) ? keys : [keys]).map((key) => [key, sessionStorage[key]]),
        ),
        set: async (values) => Object.assign(sessionStorage, values),
        remove: async (keys) => {
          for (const key of Array.isArray(keys) ? keys : [keys]) delete sessionStorage[key];
        },
      },
    },
    runtime: {
      getURL: (path) => `chrome-extension://test${path}`,
      onMessage: { addListener: (handler) => { listener = handler; } },
    },
    tabs: {
      query: () => tabQuery(),
      sendMessage: (id, message) => tabSendMessage(id, message),
    },
    identity: {
      getRedirectURL: () => 'https://test.chromiumapp.org/',
      launchWebAuthFlow: (options) => authFlow(options),
    },
  };
  globalThis.defineBackground = (callback) => callback;
  globalThis.fetch = (...args) => fetchHandler(...args);
  const { default: background } = await import('../src/entrypoints/background.ts');
  background();
  await send({ type: 'get-environment' });
  legacyRemoved = !('extensionToken' in storage);
});

beforeEach(() => {
  Bun.env.DEV = 'true';
  for (const key of Object.keys(storage)) delete storage[key];
  for (const key of Object.keys(sessionStorage)) delete sessionStorage[key];
  sentMessages.length = 0;
  tabQuery = async () => [{ id: 1 }];
  tabSendMessage = async (id, message) => { sentMessages.push({ id, message }); };
  authFlow = () => { throw new Error('Unexpected authorization'); };
  fetchHandler = () => { throw new Error('Unexpected fetch'); };
});

describe('service environments', () => {
  test('switches and restores origin-scoped credentials, rejecting stale and untrusted requests', async () => {
    expect(legacyRemoved).toBe(true);
    storage[`extensionCredentials:${origins.development}`] = credentials('dev');
    storage[`extensionCredentials:${origins['local-production']}`] = credentials('local');
    const requests = [];
    fetchHandler = async (url, options) => {
      requests.push({ origin: url.origin, authorization: options.headers.Authorization });
      return jsonResponse({ id: '1', email: 'account@example.test' });
    };

    expect((await send({ type: 'get-environment' })).environment.id).toBe('development');
    expect(await send({ type: 'set-environment', id: 'local-production' }, { ...popupSender, tab: { id: 1 } }))
      .toEqual({ ok: false });
    expect(await send({ type: 'set-environment', id: 'local-production' })).toEqual({ ok: true });
    expect(sentMessages).toEqual([{ id: 1, message: { type: 'service-environment-changed' } }]);
    expect((await send({ type: 'get-extension-account', environmentId: 'local-production' })).status).toBe('signed_in');
    expect((await send({ type: 'get-extension-account', environmentId: 'development' })).status).toBe('offline');
    await send({ type: 'set-environment', id: 'development' });
    expect((await send({ type: 'get-extension-account', environmentId: 'development' })).status).toBe('signed_in');
    expect(requests).toEqual([
      { origin: origins['local-production'], authorization: 'Bearer local' },
      { origin: origins.development, authorization: 'Bearer dev' },
    ]);
  });

  test('reports notification failures without misrepresenting the saved environment', async () => {
    tabQuery = async () => { throw new Error('Tabs unavailable'); };
    expect(await send({ type: 'set-environment', id: 'local-production' }))
      .toEqual({ ok: false, error: 'notification_failed' });
    expect((await send({ type: 'get-environment' })).environment.id).toBe('local-production');
  });

  test('an unresponsive tab does not block environment switching indefinitely', async () => {
    tabSendMessage = () => new Promise(() => {});
    const result = await Promise.race([
      send({ type: 'set-environment', id: 'local-production' }),
      new Promise((resolve) => setTimeout(() => resolve('timed out'), 2500)),
    ]);
    expect(result).toEqual({ ok: false, error: 'notification_failed' });
    expect((await send({ type: 'get-environment' })).environment.id).toBe('local-production');
  });

  test('disconnect revokes and clears only the selected environment', async () => {
    storage[`extensionCredentials:${origins.development}`] = credentials('dev');
    storage[`extensionCredentials:${origins.production}`] = credentials('prod');
    fetchHandler = async (url, options) => {
      expect(url.origin).toBe(origins.development);
      expect(options.headers.Authorization).toBe('Bearer dev');
      expect(options.redirect).toBe('error');
      return new Response(null, { status: 204 });
    };
    expect(await send({ type: 'disconnect-extension-account', environmentId: 'development' }))
      .toEqual({ ok: true });
    expect(storage[`extensionCredentials:${origins.development}`]).toBeUndefined();
    expect(storage[`extensionCredentials:${origins.production}`].token).toBe('prod');
  });

  test('finishes an in-flight authorization against its original environment', async () => {
    const started = deferred();
    const callback = deferred();
    authFlow = ({ url }) => {
      started.resolve(new URL(url));
      return callback.promise;
    };
    fetchHandler = async (url) => {
      expect(url.origin).toBe(origins.development);
      return jsonResponse({
        token: 'dev', key_id: 'key-dev', expires_at: '2030-01-01',
        user: { id: '1', email: 'dev@example.test' },
      });
    };

    const connecting = send({ type: 'connect-extension-account', environmentId: 'development' });
    const authorizationUrl = await started.promise;
    await send({ type: 'set-environment', id: 'local-production' });
    callback.resolve(`https://test.chromiumapp.org/?code=code&state=${authorizationUrl.searchParams.get('state')}`);
    expect((await connecting).ok).toBe(true);
    expect(storage[`extensionCredentials:${origins.development}`].token).toBe('dev');
    expect((await send({ type: 'get-extension-account', environmentId: 'local-production' })).status).toBe('signed_out');
  });

  test('authorizes directly against Authx with PKCE, state and nonce', async () => {
    const started = deferred();
    const callback = deferred();
    authFlow = ({ url }) => {
      started.resolve(new URL(url));
      return callback.promise;
    };

    let exchangeRequest;
    fetchHandler = async (url, options) => {
      expect(url.origin).toBe(origins.development);
      expect(url.pathname).toBe('/api/extension/authx');
      exchangeRequest = JSON.parse(options.body);
      return jsonResponse({
        token: 'authx', key_id: 'key-authx', expires_at: '2030-01-01',
        user: { id: '1', email: 'authx@example.test' },
      });
    };

    const connecting = send({ type: 'connect-extension-account', environmentId: 'development' });
    const authorizationUrl = await started.promise;

    expect(authorizationUrl.origin).toBe(authxOrigins.development);
    expect(authorizationUrl.pathname).toBe('/oidc/authorize');
    expect(authorizationUrl.searchParams.get('client_id')).toBe(extensionClientId);
    expect(authorizationUrl.searchParams.get('redirect_uri')).toBe('https://test.chromiumapp.org/');
    expect(authorizationUrl.searchParams.get('response_type')).toBe('code');
    expect(authorizationUrl.searchParams.get('scope')).toBe('openid email');
    expect(authorizationUrl.searchParams.get('code_challenge_method')).toBe('S256');
    expect(authorizationUrl.searchParams.get('code_challenge')).toBeTruthy();
    expect(authorizationUrl.searchParams.get('nonce')).toBeTruthy();

    const state = authorizationUrl.searchParams.get('state');
    callback.resolve(`https://test.chromiumapp.org/?code=code&state=${state}`);
    expect((await connecting).ok).toBe(true);

    expect(exchangeRequest).toMatchObject({
      code: 'code',
      state,
      nonce: authorizationUrl.searchParams.get('nonce'),
      redirect_uri: 'https://test.chromiumapp.org/',
    });
    expect(exchangeRequest.code_verifier).toBeTruthy();
    expect(storage[`extensionCredentials:${origins.development}`].token).toBe('authx');
    expect(Object.keys(sessionStorage)).toEqual([]);
  });

  test('a stale 401 does not erase a newly connected credential', async () => {
    storage[`extensionCredentials:${origins.development}`] = credentials('old');
    const started = deferred();
    const response = deferred();
    fetchHandler = async (url) => {
      if (url.pathname === '/api/extension/me') {
        started.resolve();
        return response.promise;
      }
      return jsonResponse({
        token: 'new', key_id: 'key-new', expires_at: '2030-01-01',
        user: { id: '1', email: 'new@example.test' },
      });
    };
    authFlow = async ({ url }) =>
      `https://test.chromiumapp.org/?code=code&state=${new URL(url).searchParams.get('state')}`;

    const checking = send({ type: 'get-extension-account', environmentId: 'development' });
    await started.promise;
    expect((await send({ type: 'connect-extension-account', environmentId: 'development' })).ok).toBe(true);
    response.resolve(new Response(null, { status: 401 }));
    await checking;
    expect(storage[`extensionCredentials:${origins.development}`].token).toBe('new');
  });

  test('production switches between HTTPS environments and keeps their credentials separate', async () => {
    Bun.env.DEV = '';
    storage[`extensionCredentials:${origins['local-production']}`] = credentials('local');
    storage[`extensionCredentials:${origins.production}`] = credentials('prod');
    const requests = [];
    fetchHandler = async (url, options) => {
      requests.push({ origin: url.origin, authorization: options.headers.Authorization });
      return jsonResponse({ id: '1', email: 'account@example.test' });
    };

    expect((await send({ type: 'get-environment' })).environment.id).toBe('local-production');
    expect((await send({ type: 'get-extension-account', environmentId: 'local-production' })).status).toBe('signed_in');
    expect(await send({ type: 'set-environment', id: 'production' })).toEqual({ ok: true });
    expect((await send({ type: 'get-environment' })).environment.id).toBe('production');
    expect((await send({ type: 'get-extension-account', environmentId: 'production' })).status).toBe('signed_in');
    expect(requests).toEqual([
      { origin: origins['local-production'], authorization: 'Bearer local' },
      { origin: origins.production, authorization: 'Bearer prod' },
    ]);
  });

  test('production rejects localhost and ignores a saved development choice', async () => {
    storage.serviceEnvironment = 'development';
    Bun.env.DEV = '';
    expect((await send({ type: 'get-environment' })).environment.id).toBe('local-production');
    expect(await send({ type: 'set-environment', id: 'development' })).toEqual({ ok: false });
    expect(await send({ type: 'set-environment', id: 'local-production' }, { ...popupSender, tab: { id: 1 } }))
      .toEqual({ ok: false });
    expect(storage.serviceEnvironment).toBe('development');
  });
});
