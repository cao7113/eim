// Authx OIDC configuration per service environment. `null` means the
// environment has not been pointed at an Authx issuer yet; the extension will
// refuse to start a login instead of silently using another environment.
const unconfiguredAuthx = {
  authxIssuer: null,
  oidcClientId: null,
} as const;

// Local production registers its Authx client at deploy time and injects the
// generated id at build time:
//   WXT_LOCAL_PRODUCTION_OIDC_CLIENT_ID=... bun run build
const localProductionOidcClientId =
  (import.meta.env.WXT_LOCAL_PRODUCTION_OIDC_CLIENT_ID as string | undefined) || null;

export const productionEnvironment = {
  id: 'production',
  label: '正式环境',
  origin: 'https://eim.fly.dev',
  ...unconfiguredAuthx,
} as const;

export const productionEnvironments = [
  {
    id: 'local-production',
    label: '本地生产',
    origin: 'https://eim.s',
    authxIssuer: 'https://authx.s',
    oidcClientId: localProductionOidcClientId,
  },
  productionEnvironment,
] as const;

export const defaultProductionEnvironment = productionEnvironments[0];

export const developmentEnvironments = [
  {
    id: 'development',
    label: '本地开发',
    origin: 'http://localhost:4003',
    authxIssuer: 'http://localhost:4000',
    oidcClientId: '00000000-0000-7000-8000-000000000004',
  },
  ...productionEnvironments,
] as const;

export type Environment = (typeof developmentEnvironments)[number];
