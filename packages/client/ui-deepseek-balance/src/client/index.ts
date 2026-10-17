/** DeepSeek account balance readout registered into the conversation composer dock. */

import type {} from '@deepseek-ai/dsh-api-remotes/client'
import type {} from '@deepseek-ai/dsh-client-locale/client'
import type { Context as ClientContext } from '@deepseek-ai/cordis'
// Type-only: merges the conversation.composer.dock SlotMap key into ui-slots.
import type {} from '@deepseek-ai/dsh-client-ui-conversation/client'
// Type-only: merges the `slots` service onto the Client Context.
import type {} from '@deepseek-ai/dsh-client-ui-renderer/client'
import { BalanceChip, type DeepSeekBalanceInjected } from './BalanceChip.tsx'
import { en, zh, type DeepSeekBalanceLocaleKey } from './locales.ts'

export type { BalanceChipProps, DeepSeekBalanceInjected } from './BalanceChip.tsx'
export type { DeepSeekBalanceLocaleKey } from './locales.ts'

declare module '@deepseek-ai/dsh-client-ui-slots' {
  interface LocaleNamespaceMap {
    /** DeepSeek balance composer-dock readout. */
    'conversation.deepseekBalance': DeepSeekBalanceLocaleKey
  }
}

/** Dictionary namespace owned by this plugin. */
export const NS = 'conversation.deepseekBalance'

/** Services required by the dock registration and generated Remote face. */
export const inject = ['slots', 'locale', 'remote', 'remote.deepseekBalance']

/** Contribute the ambient balance chip beside the shipped stats line. */
export function apply(ctx: ClientContext): void {
  ctx.effect(() => ctx.locale.register(NS, { zh, en }), 'ui-deepseek-balance: dictionaries')

  const injected = (): DeepSeekBalanceInjected => ({
    getBalance: async () => {
      const result = await ctx.remote.deepseekBalance.getBalance()
      if (!result.ok) {
        throw new Error(`deepseekBalance.getBalance failed: ${result.error.code}: ${result.error.message}`)
      }
      return result.value
    },
  })

  // Deferred until ui-conversation declares the dock slot; the stats line
  // registers at order 0, so the chip sits after it.
  ctx.slots.inject('conversation.composer.dock', () => ctx.slots.register({
    name: 'conversation.composer.dock',
    id: 'deepseekBalance',
    order: 100,
    locale: NS,
    inject: injected,
  }, BalanceChip))
}
