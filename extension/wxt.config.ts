import { defineConfig } from 'wxt';

// See https://wxt.dev/api/reference/wxt/interfaces/inlineconfig.html
export default defineConfig({
  srcDir: 'src',
  modules: ['@wxt-dev/module-svelte'],
  manifest: ({ mode }) => ({
    host_permissions:
      mode === 'development' ? ['http://localhost:4000/*'] : [],
  }),
});


