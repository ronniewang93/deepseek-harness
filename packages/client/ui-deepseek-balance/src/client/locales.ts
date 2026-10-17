/** Copy dictionaries for the DeepSeek balance composer-dock readout. */

/** Simplified Chinese dictionary and key source of truth. */
export const zh = {
  loading: '余额查询中…',
  missingCredential: '未配置 DEEPSEEK_API_KEY',
  fetchError: '余额查询失败',
  unavailable: '账户不可用',
  toppedUp: '充值',
  granted: '赠送',
  updated: '更新于',
  refresh: '点击刷新',
} satisfies Record<string, string>

/** DeepSeek balance locale key union. */
export type DeepSeekBalanceLocaleKey = keyof typeof zh

/** English dictionary checked against the Chinese key set. */
export const en = {
  loading: 'Loading balance…',
  missingCredential: 'DEEPSEEK_API_KEY not configured',
  fetchError: 'Balance fetch failed',
  unavailable: 'Account unavailable',
  toppedUp: 'Topped up',
  granted: 'Granted',
  updated: 'Updated',
  refresh: 'Click to refresh',
} satisfies Record<DeepSeekBalanceLocaleKey, string>
