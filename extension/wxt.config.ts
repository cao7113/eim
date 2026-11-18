import { defineConfig } from 'wxt';
import { defaultProductionEnvironment, developmentEnvironments, productionEnvironments } from './src/shared/environments';

const args = process.argv.slice(2);
const modeIndex = args.findIndex((arg) => arg === '--mode' || arg === '-m');
const explicitMode =
  modeIndex >= 0
    ? args[modeIndex + 1]
    : args.find((arg) => arg.startsWith('--mode='))?.slice('--mode='.length);
const mode =
  explicitMode ?? (args.some((arg) => arg === 'build' || arg === 'zip') ? 'production' : 'development');

const unpacked = process.env.WXT_UNPACKED === '1' || mode === 'development';

// Chrome derives the extension id from this public key, keeping
// chrome.identity.getRedirectURL() stable for unpacked loads (development and
// local production). Store builds omit it.
const UNPACKED_EXTENSION_KEY =
  'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtBhaX3o/RCdiDLf2oweYDNHb7CF8hoYRKuq+cYEce7aX0rNzxLGQpteeoGwgr53RoYeTrHcvrKh6gOyMoeZc1RLI8lmoi2nzlFUBPTxqse/MKDFuXStHtg9dDZVSIHmwi3JPEfRZ0b2CmyO7+RwLJWcpE8vLm/rNFdPyJELZJL1GoAQ0ivjRZWPs4POcSqiQX442EcDsKVQ+/22yTHBoh++HMcRmRCOXaUybGEIaeWnQiinuvU9YUavgs7OOjZn/x7bhBKxiYF96xQafNgzYG7vFzqLYeGjwRCJ/ALhgn28RielHt4rip37MLDtz87iNI1QbziVjoK+C7rHDyfHqFwIDAQAB';

// See https://wxt.dev/api/reference/wxt/interfaces/inlineconfig.html
export default defineConfig({
  srcDir: 'src',
  modules: ['@wxt-dev/module-svelte'],
  webExt: {
    startUrls: [mode === 'development' ? developmentEnvironments[0].origin : defaultProductionEnvironment.origin],
  },
  manifest: ({ mode }) => {
    const environments =
      mode === 'development' ? developmentEnvironments : productionEnvironments;
    const origins = environments.flatMap(({ origin, authxIssuer }) =>
      authxIssuer ? [origin, authxIssuer] : [origin],
    );

    return {
      permissions: ['storage', 'identity'],
      host_permissions: [...new Set(origins)].map((origin) => `${origin}/*`),
      ...(unpacked ? { key: UNPACKED_EXTENSION_KEY } : {}),
      browser_specific_settings: {
        gecko: { id: 'eim-helper@eim.local' },
      },
    };
  },
});
