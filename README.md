# Connection Keeper (Mantra)

```
git clone https://github.com/markoboskoauroville/connection-keeper.git && cd connection-keeper && ./build.sh && ./agent.sh load
```

Keeps the Mac online. A keeper (LaunchAgent) checks the internet every 5 minutes (ping 1.1.1.1, then an HTTP
probe), and when it is gone it walks a ladder: retry, rejoin the same Wi-Fi, join the next one in the list
(`mantra`, `Something`), switch the Wi-Fi power off and on, then back off and try again. A floating stripe shows
the connection, its live speed, the ping, the last check and the last failover, with a drop-down to switch by hand
and a gear for the list.

Stop the keeper:

```
./agent.sh unload
```

| Document | For whom |
|---|---|
| [TAKEOVER.md](TAKEOVER.md) | the next session: how it works now, the files, what has never been proven |
| [LESSONS.md](LESSONS.md) | anybody about to change a decision: what was learned and why it is so |
| [momentaryupdates.md](momentaryupdates.md) | Marko's requests, word for word, with their status |

## Press the ping (v3, 13.10.2026)

The "ping" on the stripe is a button. Press it and the stripe pings 1.1.1.1 itself (with the HTTP probe behind it), keeper running or not, and says the answer on the status line: **ALIVE ✓** and the time in green with the ping in ms, or **NOT ALIVE ✗** in red. The answer stays 20 seconds, then the usual reading returns.
