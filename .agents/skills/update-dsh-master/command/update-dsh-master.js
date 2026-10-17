/**
 * Human-facing `/update-dsh-master` command: schedules the bundled restart
 * script and settles without entering the model conversation.
 *
 * Plain ESM JavaScript, not TypeScript: the packaged Desktop runtime loads
 * profiles without a TypeScript hook, so a `.ts` entry point would resolve in
 * `dsh web` source launches and fail in the packaged application.
 *
 * @module update-dsh-master
 */

import { spawn } from 'node:child_process'
import { resolve } from 'node:path'

export const name = 'command-update-dsh-master'
export const inject = ['commands']

const SCRIPT = resolve(import.meta.dirname, '..', 'scripts', 'update-dsh-master.sh')

/**
 * Register the command. The handler only schedules detached work, because the
 * process running it is often the very service being restarted.
 *
 * @param {import('@deepseek-ai/cordis').Context} ctx - Host context carrying the command registry.
 */
export function apply(ctx) {
  ctx.effect(() => ctx.commands.register({
    name: 'update-dsh-master',
    description: 'Update master and restart the dsh web service',
    handler: () => {
      const child = spawn(SCRIPT, ['--detach'], { detached: true, stdio: 'ignore' })
      child.unref()
      return {
        kind: 'success',
        text: `dsh web restart scheduled (pid ${String(child.pid ?? 'unknown')}). `
          + 'Progress goes to ~/.dsh/update-dsh-master/logs/; reload this page once it reports ready.',
      }
    },
  }), 'update-dsh-master command')
}
