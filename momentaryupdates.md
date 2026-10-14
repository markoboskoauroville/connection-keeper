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

**Status:** built v3 13.10.2026: the "ping" on the stripe is a button; pressed, it says "pinging 1.1.1.1…" in amber, then on the status line "ALIVE ✓ <time>" in green with the ping in ms, or "NOT ALIVE ✗ no answer" / "captive portal" in red; the dot follows. The answer stays 20 s. Verified by pressing it through accessibility: ALIVE ✓ 23:50:50, ping 38 ms.

## 14.10.2026, request 5 (v4)

> is in a connection keeper. If it switches connection during its running, please color all font in red. For example, we are now working on my connection called Mantra, and then after 5 min with ping you see wow no connection. He died. His sim card is over. Then you connect to another Wi-Fi which is called something. Then you need to change the color so I know that connection is changed from distance and I need to check what's wrong with my first connection

**Status:** built v4 14.10.2026: after a failover the keeper made by itself, every word on the stripe is red and the failover field says "mantra died 09:41 → on Something" with an OK button; it stays red across restarts until OK (or a click on the red words) or until the Mac is back on the connection that died. A switch by hand never turns it red. Verified with `connection-keeperd --simulate-failover`: red seen on screen, red again after reopening the stripe, OK pressed through accessibility returned the normal colours. A real failover has not happened yet.

## 14.10.2026, request 6 (v5)

> for connection keeper, you can now test it with a second connection. Now I have two Wi-Fi as mentioned. Mantra and something switch 5 min each connection a few times and then see if it's everything working

> please switch to Mantra connection and keep it live. I'm taking my phone. If one connection is dead and the app cannot find another connection, it needs to give me a warning. It needs to write on the status that no another connection, and then I know that I need to do something about it. I just try to switch to another connection. There is a name something of the Wi-Fi I click okay. There is mantra another connection. I click on mantra, and then nothing is happening. It's not switching immediately. That's very bad.

**Status:** built v5 14.10.2026. The live test found why the click on mantra did nothing: on macOS 15 networksetup
cannot join a protected Wi-Fi without its password. v5: the drop-down switches at once from the stripe and says
"switching to …" then "on mantra ✓" or the reason in red; joins go networksetup → the password typed once in ⚙ →
Control Centre through accessibility; "NO OTHER CONNECTION — mantra dead, Something not working" in bold red when
nothing works. Waiting for Marko: type both Wi-Fi passwords in ⚙ → Password…, or allow Accessibility for the app.

## 14.10.2026, request 7 (v6)

> for connectionkeeper, please keep it always on top, which can be changed in the settings. I want to do both option 1 and option 2. I want to do password there and also allow accessibility.

**Status:** in work 14.10.2026. Marko enabled Accessibility for Connection Keeper the same day.
