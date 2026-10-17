/**
 * DeepSeek account balance Remote: resolves the harness `DEEPSEEK_API_KEY`
 * credential per fetch and projects `/user/balance` for trusted clients.
 *
 * @module @deepseek-ai/dsh-host-deepseek-balance
 */

import type { Context } from '@deepseek-ai/cordis'
import { Remote, TypertRemoteService } from '@deepseek-ai/dsh-typert-protocol'
// Typert-generated ./typert and ./remote artifacts import Zod at runtime.
import type {} from 'zod'
// Side-effect type import: declaration-merges `ctx.credentials` onto Context.
import type {} from '@deepseek-ai/dsh-credentials'
import type { CredentialRef } from '@deepseek-ai/dsh-credentials/types'
import type { DeepSeekBalanceInfo, DeepSeekBalanceSnapshot } from './types.ts'

export type * from './types.ts'

/** Upstream endpoint path appended to the base URL. */
const BALANCE_PATH = '/user/balance'
/** Official DeepSeek API base; override with `DSH_DEEPSEEK_BALANCE_BASE_URL`. */
const DEFAULT_BASE_URL = 'https://api.deepseek.com'
/** Credential reference resolved through `ctx.credentials` on every upstream fetch. */
const CREDENTIAL_REF = 'DEEPSEEK_API_KEY' as CredentialRef
/** Consecutive calls inside this window share one upstream fetch. */
const CACHE_TTL_MS = 60_000
/** Upstream request timeout. */
const REQUEST_TIMEOUT_MS = 10_000

/** Minimal shape of the upstream `/user/balance` response body. */
interface UpstreamBalanceBody {
  is_available?: boolean
  balance_infos?: Array<{
    currency?: string
    total_balance?: string
    granted_balance?: string
    topped_up_balance?: string
  }>
}

/** Remote-only service exposing the DeepSeek account balance, cached briefly. */
export class DeepSeekBalanceGateway extends TypertRemoteService {
  static inject = ['credentials']

  private cachedAt = -Infinity
  private cachedSnapshot: DeepSeekBalanceSnapshot = {
    available: false,
    balances: [],
    fetchedAt: null,
    error: 'NOT_FETCHED',
  }

  constructor(ctx: Context) {
    super(ctx, 'deepseekBalance')
  }

  /** Read the balance; calls within the TTL share one upstream request. */
  @Remote('getBalance')
  async getBalance(): Promise<DeepSeekBalanceSnapshot> {
    if (Date.now() - this.cachedAt < CACHE_TTL_MS) return this.cachedSnapshot
    const snapshot = await this.fetchNow()
    this.cachedAt = Date.now()
    this.cachedSnapshot = snapshot
    return snapshot
  }

  private async fetchNow(): Promise<DeepSeekBalanceSnapshot> {
    let apiKey: string | undefined
    try {
      apiKey = (await this.ctx.credentials.resolve(CREDENTIAL_REF))?.value
    } catch {
      apiKey = undefined
    }
    if (apiKey === undefined || apiKey.length === 0) {
      return { available: false, balances: [], fetchedAt: null, error: 'MISSING_CREDENTIAL' }
    }
    const baseURL = process.env.DSH_DEEPSEEK_BALANCE_BASE_URL ?? DEFAULT_BASE_URL
    try {
      const response = await fetch(`${baseURL}${BALANCE_PATH}`, {
        headers: { authorization: `Bearer ${apiKey}` },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      })
      if (!response.ok) {
        return { available: false, balances: [], fetchedAt: null, error: `HTTP_${response.status}` }
      }
      const body = await response.json() as UpstreamBalanceBody
      const balances: DeepSeekBalanceInfo[] = (body.balance_infos ?? []).map(info => ({
        currency: info.currency ?? '',
        totalBalance: info.total_balance ?? '0',
        grantedBalance: info.granted_balance ?? '0',
        toppedUpBalance: info.topped_up_balance ?? '0',
      }))
      return {
        available: body.is_available ?? balances.length > 0,
        balances,
        fetchedAt: Date.now(),
        error: null,
      }
    } catch (error) {
      return {
        available: false,
        balances: [],
        fetchedAt: null,
        error: error instanceof Error ? error.message : String(error),
      }
    }
  }
}

export default DeepSeekBalanceGateway
