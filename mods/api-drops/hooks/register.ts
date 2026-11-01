// api-drops (Marko, 1.11.2026, connection-keeper request 65): "create a mod for Claude Code which is going to detect
// drops of connection with the API ... mark this inside the status line". The watcher is ck-claude, started by
// Network Aggregate Connection Keeper (Mantra); it follows every session's transcript and probes the API with a TLS
// handshake every 30 s. This mod reads its state file and shows one status entry in every session:
//   ☁ API ✓ 65 ms                         nothing dropped in the last 30 minutes
//   ☁ API drop 05:20 EPROTO×10 · 348 s    a drop in the last 30 minutes (and how it ended)
//   ☁ API RETRYING since 05:20 EPROTO×3   a session is retrying now
//   ☁ API NOT REACHABLE (tls: timed out)  the probe cannot reach api.anthropic.com
//   ☁ API ? (Connection Keeper off)       no watcher: its state is older than 2 minutes
import type { Register } from 'claude-code'

const STATE = '/Users/markobosko/Library/Application Support/connection-keeper/claude-drops-state.json'

type Snap = { mode?: string; tunnel?: boolean; via?: string }
type State = {
  updated?: string
  probe?: { ok?: boolean; tcp?: { ms?: number; error?: string }; dns?: { error?: string } }
  last?: { start?: string; kinds?: Record<string, number>; open?: boolean; seconds?: number; recovered?: boolean; folder?: string; snap?: Snap }
}

const hm = (iso: string) => iso.slice(11, 16)

function line(s: State, nowMs: number): string {
  const age = s.updated ? nowMs - Date.parse(s.updated) : Infinity
  if (age > 120_000) return '☁ API ? (Connection Keeper off)'
  const p = s.probe ?? {}
  if (p.ok === false) return `☁ API NOT REACHABLE (${p.tcp?.error ?? p.dns?.error ?? '?'})`
  const l = s.last
  if (l?.start) {
    const kinds = Object.entries(l.kinds ?? {}).map(([k, v]) => `${k}×${v}`).join(' ')
    if (l.open) return `☁ API RETRYING since ${hm(l.start)} ${kinds}`
    if (nowMs - Date.parse(l.start) < 1_800_000)
      return `☁ API drop ${hm(l.start)} ${kinds} · ${l.recovered ? 'back' : 'gave up'} after ${l.seconds ?? '?'} s`
  }
  return `☁ API ✓ ${p.tcp?.ms ?? '?'} ms`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const r = await next(e)
    const tick = async () => {
      try {
        $.ui.status(line(JSON.parse(await $.fs.read(STATE)) as State, await $.clock.now()))
      } catch {
        $.ui.status('☁ API ? (Connection Keeper off)')
      }
    }
    await tick()
    $.clock.every(10_000, tick)
    return r
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.reason === 'error')
      $.ui.toast('☁ The turn ended on an API error: Connection Keeper wrote the state of the lines at that second (ck-claude report).')
    return r
  })
}
