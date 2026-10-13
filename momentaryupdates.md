# connection-keeper: momentary updates

Every request from Marko, word for word, before any code. Each item has a Status line.

## 13.10.2026, request 1 (v1)

> please work through my troubles with connections with internet. I have 2 access points. One is called Mantra, the other is called something. You need to create a demon which checks internet connection every 5 min. If there is no internet connection, it needs to connect to another wireless point and continue through there, and vice versa. So it needs to work in a background and intelligently checking the internet every 5 min ping to the 1.1.1.1. If it's working, go to sleep next 5 min and then if it's not working, you switch the Wi-Fi's to find does something or Mantra is working. Some of these two needs to work, so we have now redundant connections to the internet. And you need to find the way out of the problem if there is no connection intelligently. This is also one of the repositories in GitHub connection-keeper for macOS. And we're going to find more ways to keep connected. But for now we have only two. So this it needs to have scope of expansion, and it's going to in future find also wired connections and so on. So basically switching connections if connection drops and it's for some reason doesn't work, it needs to find intelligently and connect to another point

**Status:** v1 built 13.10.2026 (keeper + ladder + dry run, verified in simulation); waits for Marko's live failover test.

## 13.10.2026, request 2 (v1)

> And this application has a controller as a Swift app. And this Swift app just looks like one stripe. It is kind of status line floating around, which shows the current connection and the traffic speed. And maybe some more of useful data you think are useful. Basically, it's a network monitor, connection monitor, and I can also manually switch to mantra or to Something. There will be drop-down menu from connections and these connections we can expand in the future. So there will be setting gear when I can choose connections.

**Status:** v1 built 13.10.2026: the stripe (connection, speed, ping, last check, failover, drop-down, gear with the list) seen on screen; the manual switch not yet clicked.

## 13.10.2026, request 3 (v2)

> to the app which keeps connection, please add a speed test button in the settings so I can speed test every connection available there

**Status:** built v2 13.10.2026: a Speed test button on every Wi-Fi row in Settings and Speed test all; macOS networkQuality bound to the Wi-Fi; another network is joined after a warning, measured and left again; the keeper holds its checks meanwhile. The result (↓ ↑ Mbit/s, ms, time) stays beside the row. Marko to try.

## 13.10.2026, request 4 (v3)

> please update the app for keeping my connection alive. There is a ping in the user interface. I want to press the ping and then it pings and tells me if my connection is alive or not. Exactly, there status line exactly on the status line

**Status:** in progress.
