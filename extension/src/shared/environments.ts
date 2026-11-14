export const productionEnvironment = {
  id: 'production',
  label: '正式环境',
  origin: 'https://eim.fly.dev',
} as const;

export const productionEnvironments = [
  { id: 'local-production', label: '本地生产', origin: 'https://eim.s' },
  productionEnvironment,
] as const;

export const defaultProductionEnvironment = productionEnvironments[0];

export const developmentEnvironments = [
  { id: 'development', label: '本地开发', origin: 'http://localhost:4000' },
  ...productionEnvironments,
] as const;

export type Environment = (typeof developmentEnvironments)[number];
