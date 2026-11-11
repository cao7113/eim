import { defineConfig } from 'wxt';

const args = process.argv.slice(2);
const modeIndex = args.findIndex((arg) => arg === '--mode' || arg === '-m');
const explicitMode =
  modeIndex >= 0
    ? args[modeIndex + 1]
    : args.find((arg) => arg.startsWith('--mode='))?.slice('--mode='.length);
const mode =
  explicitMode ?? (args.some((arg) => arg === 'build' || arg === 'zip') ? 'production' : 'development');

// See https://wxt.dev/api/reference/wxt/interfaces/inlineconfig.html
export default defineConfig({
  srcDir: 'src',
  modules: ['@wxt-dev/module-svelte'],
  webExt: {
    startUrls: [mode === 'development' ? 'http://localhost:4000' : 'https://github.com'],
  },
  manifest: ({ mode }) => ({
    permissions: ['storage', 'identity'],
    host_permissions:
      mode === 'development' ? ['http://localhost:4000/*'] : [],
  }),
});
