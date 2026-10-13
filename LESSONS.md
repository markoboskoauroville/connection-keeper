# connection-keeper: lessons

## The decisions

- **The SSID comes from `ipconfig getsummary`, not CoreWLAN.** Since macOS 14, CoreWLAN and
  `networksetup -getairportnetwork` hide the SSID from a process without Location permission ("You are not
  associated with an AirPort network" while connected to `mantra`, measured 13.10.2026). `ipconfig getsummary en0`
  still names it. A LaunchAgent cannot ask for Location, so this keeps the keeper free of any permission.
- **Ping and HTTP, not ping alone.** A network that blocks ICMP is not an outage; the HTTP probe decides.
  Measured 13.10.2026: with the ping pointed at 192.0.2.1 the keeper said "online via mantra (http (ping blocked))".
- **One file each way, not a socket or a port.** state.json out, command.json in. Nothing to collide with in
  `ports.md`, and the stripe can show the last state even with the keeper dead.
- **No fail-back.** Returning to the first network whenever it works again would flap between two access points
  when one is marginal. Rejected for v1; a "prefer the first" switch can be added if Marko wants it.
- **The keeper lives inside the app bundle.** One install, one signature ("Mantra Apps"), and the LaunchAgent
  points at `/Applications/…/connection-keeperd`.
- **Drivers per kind.** Marko: "it's going to in future find also wired connections". Only the driver is new for
  a new kind; the ladder and the list stay.

## The traps

- `networksetup` exits 0 on failure and prints the reason; read the words, then check the SSID and the IP.
- `screencapture -x` of the whole screen captures only the main display; the stripe was on the second one.
  `screencapture -l <windowid>` captures the window itself.
- Two keepers (a test beside the agent) would fight; the flock on `keeper.lock` makes the second one leave.
