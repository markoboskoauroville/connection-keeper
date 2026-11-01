# api-drops

Shows Claude Code's connection to the API in the status line of every session: `☁ API ✓ 65 ms`, a recent drop with
its kind (ENOTFOUND, ECONNRESET, EPROTO) and how it ended, `RETRYING` while a session retries, or `NOT REACHABLE` when
the TLS probe to api.anthropic.com fails. The data comes from `ck-claude`, the watcher that Network Aggregate
Connection Keeper (Mantra) runs (github.com/markoboskoauroville/connection-keeper, Tools/ck-claude). It follows every
transcript and writes the state of the lines at the second of each drop. A turn that ends on an API error also gets a toast.
