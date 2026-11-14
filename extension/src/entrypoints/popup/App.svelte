<script lang="ts">
  import { onMount } from 'svelte';
  import type {
    DictionaryConnection,
    ExtensionAccount,
    ExtensionActionResult,
    ExtensionAuthResult,
  } from '../../shared/dictionary';
  import { developmentEnvironments, productionEnvironments, type Environment } from '../../shared/environments';

  let enabled = $state(true);
  let connection = $state<'checking' | DictionaryConnection['status']>('checking');
  let account = $state<ExtensionAccount>({ status: 'signed_out' });
  let saving = $state(false);
  let authBusy = $state(false);
  let settingsError = $state('');
  let authError = $state('');
  let environment = $state<Environment | null>(null);
  let environmentBusy = $state(false);
  let environmentError = $state('');
  let environmentVersion = 0;
  const environmentOptions = import.meta.env.DEV ? developmentEnvironments : productionEnvironments;

  onMount(() => {
    void loadLookupSetting();
    void refreshEnvironment();

    const onStorageChanged = (changes: Record<string, unknown>, area: string) => {
      if (area === 'local' && changes.serviceEnvironment) void refreshEnvironment();
    };
    browser.storage.onChanged.addListener(onStorageChanged);
    return () => browser.storage.onChanged.removeListener(onStorageChanged);
  });

  async function refreshEnvironment() {
    const version = ++environmentVersion;
    environmentError = '';
    connection = 'checking';
    account = { status: 'signed_out' };
    try {
      const result = await browser.runtime.sendMessage({ type: 'get-environment' }) as
        { environment: Environment } | { error: string };
      if (version !== environmentVersion) return;
      if (!('environment' in result)) throw new Error('Environment unavailable');
      environment = result.environment;
      void refreshConnection(version);
      void refreshAccount(version);
    } catch (error) {
      console.error('Unable to load service environment:', error);
      if (version === environmentVersion) {
        environment = null;
        connection = 'offline';
        account = { status: 'offline' };
        environmentError = '无法读取服务环境，请重试。';
      }
    }
  }

  async function changeEnvironment(event: Event) {
    const id = (event.currentTarget as HTMLSelectElement).value;
    environmentBusy = true;
    environmentError = '';
    try {
      const result = await browser.runtime.sendMessage({ type: 'set-environment', id });
      if (!result?.ok) {
        if (result?.error === 'notification_failed') {
          await refreshEnvironment();
          environmentError = '环境已切换，部分页面可能未更新，请刷新页面。';
          return;
        }
        throw new Error('Environment change failed');
      }
      await refreshEnvironment();
    } catch (error) {
      console.error('Unable to change service environment:', error);
      environmentError = '切换环境失败，请重试。';
      await refreshEnvironment();
      environmentError = '切换环境失败，请重试。';
    } finally {
      environmentBusy = false;
    }
  }

  async function loadLookupSetting() {
    try {
      const settings = (await browser.runtime.sendMessage({
        type: 'get-lookup-setting',
      })) as { enabled: boolean };
      enabled = settings.enabled;
    } catch (error) {
      console.error('Unable to load extension settings:', error);
      settingsError = '无法读取插件设置。';
    }
  }

  async function refreshConnection(version = environmentVersion) {
    if (!environment) return;
    connection = 'checking';

    try {
      const result = (await browser.runtime.sendMessage({
        type: 'check-api-connection',
        environmentId: environment.id,
      })) as DictionaryConnection;
      if (version === environmentVersion) connection = result.status;
    } catch (error) {
      console.error('Unable to check dictionary service:', error);
      if (version === environmentVersion) connection = 'offline';
    }
  }

  async function toggleLookup() {
    saving = true;
    settingsError = '';
    const nextEnabled = !enabled;

    try {
      const result = await browser.runtime.sendMessage({
        type: 'set-lookup-setting',
        enabled: nextEnabled,
      });

      if (!result?.ok) throw new Error('Background could not save the setting');
      enabled = nextEnabled;
    } catch (error) {
      console.error('Unable to save extension settings:', error);
      settingsError = '保存设置失败，请重试。';
    } finally {
      saving = false;
    }
  }

  async function refreshAccount(version = environmentVersion) {
    if (!environment) return;
    try {
      const result = (await browser.runtime.sendMessage({
        type: 'get-extension-account',
        environmentId: environment.id,
      })) as ExtensionAccount;
      if (version === environmentVersion) account = result;
    } catch (error) {
      console.error('Unable to load extension account:', error);
      if (version === environmentVersion) account = { status: 'offline' };
    }
  }

  async function connectAccount() {
    if (!environment) return;
    const version = environmentVersion;
    authBusy = true;
    authError = '';

    try {
      const result = (await browser.runtime.sendMessage({
        type: 'connect-extension-account',
        environmentId: environment.id,
      })) as ExtensionAuthResult;

      if (version !== environmentVersion) return;
      if (!result.ok) {
        authError =
          result.error === 'unavailable'
            ? '无法连接 Eim 服务，请稍后重试。'
            : '登录连接失败，请重新尝试。';
        return;
      }

      account = result.account;
    } catch (error) {
      console.error('Extension account authorization failed:', error);
      if (version === environmentVersion) authError = '登录已取消或连接失败，请重试。';
    } finally {
      authBusy = false;
    }
  }

  async function disconnectAccount() {
    if (!environment) return;
    const version = environmentVersion;
    authBusy = true;
    authError = '';

    try {
      const result = (await browser.runtime.sendMessage({
        type: 'disconnect-extension-account',
        environmentId: environment.id,
      })) as ExtensionActionResult;

      if (version !== environmentVersion) return;
      if (result.ok) {
        account = { status: 'signed_out' };
      } else {
        authError =
          result.error === 'unavailable'
            ? '无法连接 Eim 服务，凭据尚未撤销。请稍后重试。'
            : '退出失败，凭据尚未撤销。请重试。';
      }
    } catch (error) {
      console.error('Extension account disconnect failed:', error);
      if (version === environmentVersion) authError = '退出失败，凭据尚未撤销。请重试。';
    } finally {
      authBusy = false;
    }
  }

</script>

<main class="panel">
  <header class="brand">
    <div class="brand-mark" aria-hidden="true">e</div>
    <div>
      <p class="eyebrow">ENGLISH IN CONTEXT</p>
      <h1>Eim 划词助手</h1>
    </div>
  </header>

  <section class="setting-card" aria-labelledby="lookup-setting-title">
    <div class="setting-copy">
      <h2 id="lookup-setting-title">划词查词</h2>
      <p>{enabled ? '选中单词或短语时自动显示释义' : '已暂停，不会自动查询'}</p>
    </div>
    <button
      class:enabled
      class="switch"
      type="button"
      role="switch"
      aria-checked={enabled}
      aria-label="启用划词查词"
      disabled={saving}
      onclick={toggleLookup}
    >
      <span></span>
    </button>
  </section>

  <section class="service-card" aria-live="polite">
    <div class="service-heading">
      <div>
        <p class="eyebrow">DICTIONARY SERVICE</p>
        <h2>词典服务</h2>
      </div>
      <span class:online={connection === 'connected'} class:offline={connection === 'offline'} class="status-dot"></span>
    </div>
    <label class="environment-label" for="service-environment">服务环境</label>
    <select
      id="service-environment"
      class="environment-select"
      value={environment?.id ?? ''}
      disabled={environmentBusy || authBusy || !environment}
      onchange={changeEnvironment}
    >
      {#if !environment}<option value="">正在读取环境…</option>{/if}
      {#each environmentOptions as option}
        <option value={option.id}>{option.label} · {option.origin}</option>
      {/each}
    </select>
    <p class="service-status">
      {#if connection === 'checking'}
        正在检查连接…
      {:else if connection === 'connected'}
        服务已连接
      {:else if connection === 'unconfigured'}
        当前版本尚未配置服务地址
      {:else}
        无法连接服务，请检查当前环境和网络
      {/if}
    </p>
    <button class="text-button" type="button" onclick={() => environment ? refreshConnection() : refreshEnvironment()} disabled={connection === 'checking'}>
      重新检查
    </button>
  </section>

  {#if environmentError}
    <p class="error-message" role="alert">{environmentError}</p>
  {/if}
  {#if settingsError}
    <p class="error-message" role="alert">{settingsError}</p>
  {/if}

  <section class="account">
    <div>
      <h2>连接 Eim 账号</h2>
      {#if account.status === 'signed_in'}
        <p>已登录：{account.email}</p>
      {:else if account.status === 'offline' && account.email}
        <p>{account.email} · 服务暂时离线</p>
      {:else if account.status === 'offline'}
        <p>无法验证账号状态，请检查服务连接。</p>
      {:else}
        <p>登录后即可使用账号同步功能。</p>
      {/if}
    </div>
    {#if account.status === 'signed_in' || (account.status === 'offline' && account.email)}
      <button class="login-button secondary" type="button" disabled={authBusy || environmentBusy || !environment} onclick={disconnectAccount}>
        退出登录
      </button>
    {:else}
      <button class="login-button" type="button" disabled={authBusy || environmentBusy || !environment} onclick={connectAccount}>
        {authBusy ? '连接中…' : '登录连接'}
      </button>
    {/if}
  </section>

  {#if authError}
    <p class="error-message" role="alert">{authError}</p>
  {/if}

  <footer>
    收藏与笔记将保存到你的 Eim 学习中心
  </footer>
</main>
