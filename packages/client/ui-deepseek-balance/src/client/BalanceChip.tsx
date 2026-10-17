import { memo, useCallback, useEffect, useRef, useState } from 'react'
import type { DeepSeekBalanceSnapshot } from '@deepseek-ai/dsh-api-remotes/client'
import { Tooltip } from '@deepseek-ai/dsh-client-ui-primitives'
import type { InjectFace, PropsLocale } from '@deepseek-ai/dsh-client-ui-slots'
import type { DeepSeekBalanceLocaleKey } from './locales.ts'
import css from './BalanceChip.module.css'

/** Registration-side Remote face used by the chip. */
export interface DeepSeekBalanceInjected {
  /** Read a current DeepSeek account balance snapshot. */
  getBalance: () => Promise<DeepSeekBalanceSnapshot>
}

/** Full component props assembled by the composer-dock slot renderer. */
export type BalanceChipProps =
  InjectFace<DeepSeekBalanceInjected>
  & PropsLocale<'conversation.deepseekBalance'>

/** Background refresh cadence; the Host also caches upstream for 60s. */
const REFRESH_INTERVAL_MS = 60_000

/** Display symbols for currencies the upstream reports. */
const CURRENCY_SYMBOLS: Record<string, string> = { CNY: '¥', USD: '$', EUR: '€', GBP: '£' }

type ViewState =
  | { readonly status: 'loading' }
  | { readonly status: 'error'; readonly message: string }
  | { readonly status: 'ready'; readonly snapshot: DeepSeekBalanceSnapshot }

/** Currency symbol falling back to the raw code. */
function symbolOf(currency: string): string {
  return CURRENCY_SYMBOLS[currency] ?? `${currency} `
}

/** Local time `HH:MM` for the fetched-at tooltip line. */
function formatTime(epochMs: number): string {
  const date = new Date(epochMs)
  return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}:${String(date.getSeconds()).padStart(2, '0')}`
}

/** Error-copy key for stable upstream failure reasons. */
function errorKeyOf(error: string): DeepSeekBalanceLocaleKey {
  if (error === 'MISSING_CREDENTIAL') return 'missingCredential'
  return 'fetchError'
}

/**
 * Ambient DeepSeek balance readout: polls the Host Remote on mount and on an
 * interval, and refreshes immediately on click.
 */
export const BalanceChip = memo(function BalanceChip({ getBalance, t }: BalanceChipProps) {
  const [view, setView] = useState<ViewState>({ status: 'loading' })
  const requestSeq = useRef(0)

  const refresh = useCallback(async () => {
    const seq = ++requestSeq.current
    try {
      const snapshot = await getBalance()
      if (seq === requestSeq.current) setView({ status: 'ready', snapshot })
    } catch (error) {
      if (seq === requestSeq.current) {
        setView({ status: 'error', message: error instanceof Error ? error.message : String(error) })
      }
    }
  }, [getBalance])

  useEffect(() => {
    void refresh()
    const timer = setInterval(() => void refresh(), REFRESH_INTERVAL_MS)
    return () => clearInterval(timer)
  }, [refresh])

  if (view.status === 'loading') {
    return <span className={css.root}>{t('loading')}</span>
  }

  if (view.status === 'error') {
    return (
      <Tooltip label={view.message} side="top" delayMs={300}>
        <button type="button" className={`${css.root} ${css.warning}`} onClick={() => void refresh()}>
          <span>DeepSeek</span>
          <span>{t('fetchError')}</span>
        </button>
      </Tooltip>
    )
  }

  const { snapshot } = view
  if (snapshot.error !== null) {
    const message = `${t(errorKeyOf(snapshot.error))} (${snapshot.error})`
    return (
      <Tooltip label={message} side="top" delayMs={300}>
        <button type="button" className={`${css.root} ${css.warning}`} onClick={() => void refresh()}>
          <span>DeepSeek</span>
          <span>{t(errorKeyOf(snapshot.error))}</span>
        </button>
      </Tooltip>
    )
  }

  const primary = snapshot.balances[0]
  if (primary === undefined || !snapshot.available) {
    return (
      <Tooltip label={t('unavailable')} side="top" delayMs={300}>
        <button type="button" className={`${css.root} ${css.warning}`} onClick={() => void refresh()}>
          <span>DeepSeek</span>
          <span>{t('unavailable')}</span>
        </button>
      </Tooltip>
    )
  }

  const detail = snapshot.balances
    .map(info => `${symbolOf(info.currency)}${info.totalBalance} (${t('toppedUp')} ${info.toppedUpBalance} · ${t('granted')} ${info.grantedBalance})`)
    .join('\n')
  const updatedLine = snapshot.fetchedAt === null ? '' : `${t('updated')} ${formatTime(snapshot.fetchedAt)}`
  const label = [detail, updatedLine, t('refresh')].filter(line => line.length > 0).join('\n')

  return (
    <Tooltip label={label} side="top" delayMs={300}>
      <button type="button" className={css.root} onClick={() => void refresh()}>
        <span>DeepSeek</span>
        <span className={css.amount}>{`${symbolOf(primary.currency)}${primary.totalBalance}`}</span>
      </button>
    </Tooltip>
  )
})
