/**
 * Client-safe type surface of the DeepSeek balance Remote. Types only — no
 * runtime code, and nothing here reaches a Host-only symbol, so a Client
 * compilation face reads exactly the signature the Host emits.
 *
 * @module @deepseek-ai/dsh-host-deepseek-balance/types
 */

/** One currency balance reported by the DeepSeek `/user/balance` endpoint. */
export interface DeepSeekBalanceInfo {
  /** ISO-style currency code reported upstream, such as `CNY`. */
  readonly currency: string
  /** Total remaining balance as an upstream decimal string. */
  readonly totalBalance: string
  /** Granted (non-top-up) portion as an upstream decimal string. */
  readonly grantedBalance: string
  /** Topped-up portion as an upstream decimal string. */
  readonly toppedUpBalance: string
}

/** Point-in-time balance snapshot returned by the DeepSeek balance Remote. */
export interface DeepSeekBalanceSnapshot {
  /** Upstream `is_available` flag; false while the account cannot spend. */
  readonly available: boolean
  /** One entry per currency the upstream account holds. */
  readonly balances: readonly DeepSeekBalanceInfo[]
  /** Epoch milliseconds of the successful upstream fetch; null when none succeeded yet. */
  readonly fetchedAt: number | null
  /** Stable failure reason of the last attempt; null on success. */
  readonly error: string | null
}
