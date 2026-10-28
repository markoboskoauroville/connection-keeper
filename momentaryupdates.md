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

**Status:** built v6 14.10.2026. The stripe is always on top (status-bar level, every Space, beside full-screen apps),
⚙ → Always on top turns it off and on, remembered (measured: layer 25 on, 0 off). Accessibility is granted and
survived the rebuild; `--check-join` read Control Centre's Wi-Fi list (mantra, Something) without pressing anything.
Waiting for Marko: ⚙ → Password… for mantra and for Something (option 1); no prompt of any kind comes from the app.

## 14.10.2026, request 8 (v7)

> please in my connection keeper reduce the space between the text and just put pipes in between. There is too much empty space and this dialogue is taking unnecessary length

**Status:** built v7 14.10.2026: the items sit close with a dim " | " between them and the stripe is as wide as its
words (540 instead of 797 points in the normal state; docs/v7-stripe.png). Red and NO OTHER CONNECTION still fit
(docs/v7-no-other-connection.png). Found and fixed on the way: the stripe's remembered place was off every screen
(x = -2247), so it was invisible; it now comes back to the main screen when that happens.

## 14.10.2026, request 9 (v8)

> a new feature for Connection Keeper is to know how much megabytes are left on my account. This is how to get it: by sending SMS to this number, so my TP-Link can do this. You have links you can open my browser Firefox, control it remotely, and get the number. Please check it right now. I send the SMS and I immediately receive the remaining megabytes/gigabytes status and forward this information right to the Connection Keeper. Connection Keeper can also have a way to send SMS through the Firefox when I ask to check the current status of gigabytesb For Telemach Croatia, the text to send is STANJE (the Croatian word for "balance"), to the number 13880.

## 14.10.2026, request 10 (v8)

> now build the script right inside the connectionkeeper so I don't need AI or anything. It's a fixed script to open the Firefox control, it remotely sends SMS, reads SMS, and writes the data. Write in the status of megabytes for the time we asked

## 14.10.2026, request 11 (v8, change of design)

> can we build a server headless browser for exactly this function? To use this device to connect with SMS and actually send any SMS using the device and read the response. But right now we're just using it for the status of the megabytes in the card itself


## 14.10.2026, request 12 (v8, refining)

> I want to speed up the process and also the user interface. It means connector keeper can ask the remaining megabytes only through a headless browser through the command in Python or any other command in C++. So it all works behind the scenes

**Status (requests 9 to 12):** built v8 14.10.2026. The stripe shows "28.2 GB left · 13:00" (docs/v8-data-balance.png); a click or ⚙ → Check data runs `router-sms balance --json` behind the scenes (repo router-sms: a headless Firefox of its own sends STANJE to 13880 through the TP-Link and reads Telemach's reply). Two real checks, 12:58 and 13:00: 28837.12 MB left of 102400 MB, 13.6 s and 11.4 s from the click. Automatic check in ⚙, off by default (one SMS each).

## 14.10.2026, request 13 (v9)

> please update the connection keeper. Please see the latest screenshot on the desktop. What's going on here? In the settings, we have cutting text. It's too close to the edge. Also, I want to have in settings the unit of measurement of speed. Different options or automatic, depending on the speed you go from kilobits to megabits. We have megabytes, so any standard practices of measuring measurement, the standard units we need to have in the settings to change. Also, as the numbers are changing on the speed, the whole status line is breathing. So I'm trying to click on the settings icon and it's moving. You should solve this somehow. There should be maybe a fixed number of places for numbers, so the thing doesn't stretch over time

**Status:** built v9 14.10.2026. Settings sizes itself to its content with 20 points of margin (docs/v9-settings.png); ⚙ → Speed unit: Auto in bits (default) or bytes, or any fixed unit from bit/s to GB/s; every item on the stripe has a fixed width and the numbers four places, ⚙ moved to the left end, so nothing moves while the numbers change (three shots 3 s apart: 956 points each in bits, 926 in bytes).

## 14.10.2026, request 14 (v10)

> Please check what connection keeper is doing. I think it's measuring my local network transfer. It should only show the speed of internet transfer, never local.

**Status:** built v10 14.10.2026. It was so: the stripe counted every byte on en0, the phone included. Now it shows **internet** only, the bytes of the default route through the router (TCP and UDP). During a 150 MB adb push to the phone at 3.6–3.9 MB/s, the stripe showed 0–26 kB/s up (docs/v10-stripe-during-adb-2.png).

## 18.10.2026, request 15 (v11, change of design)

> my connection keeper application has problems sending SMS and receiving SMS. Please let's change it. When I click to check the available beta, you need to create action to open Chrome browser, go to this address, type this password and be inside, and send SMS by using Claude plugin. And then like invisible hand, it's needed to do it in front of my eyes using this interface http://192.168.1.1/ pasword is [the router password]

(The password is not repeated here; the script reads it from ~/Downloads/API/tplink.md.)

Then, in the same session:

> can also work in Firefox if you can easily remote control the Firefox. There is already some kind of way to control Firefox, I think that's even better. Let's try with Firefox so I can also see you log in everything remotely. I think the script can do it without launching Claude once. It's done the same script only does it over and over again

> anyhow, I want to see as some person is doing it. I want to see how you open the Firefox, write SMS, and when the answer comes you switch exactly to that message and open the message for me

**Status:** built v11 18.10.2026 with router-sms v2 `--visible`: a Firefox window he watches, the password and the
SMS typed letter by letter, the reply opened and held 15 s. No Claude (the AI may not type the router password; the
script does). Proven without an SMS (`router-sms inbox --visible`, 20–30 s). The warm router-sms server is stopped:
it held the router's only session and was why the check failed ("no New Message form"). The first real check is
Marko's click on the stripe. **Marko, 18.10.2026: "I clicked on GB. Left it everything looks fantastic"** — confirmed.

## 18.10.2026, request 16

> a new feature in the app is when I click on download speed, it tests download speed. When I click on upload speed, it tests upload speed and gives me the test results

> also same principle for speed test. When I click speed, you are going to open the speedtest.net and test the speeds. Next to (upload and download) current speed, you just keep the last result so Firefox is ideal for this kind of thing because it can be easily controlled remotely with fixed script without cloud at the end

**Status:** built v11 18.10.2026: `test ↓ 33.1 ↑ 25.2 · 01:15` beside the live speed; a click on it or on the live
speed runs speedtest.net in a Firefox window he watches (Tools/speedtest-firefox, no AI). speedtest.net measures
download and upload in one run, so either click gives both.

## 18.10.2026, request 17

> every time an app starts, it needs to check SMS in the background and give me the GB left. Same for the speed test. Also in the background do the speed test so running the app. Meaning I need to have the values for this day

> so during running, nothing is happening in front of my eyes. Everything in the background. When I manually click, it's happening in front of my eyes

**Status:** built v11 18.10.2026: 5 s after the start the data check, then the speed test, both headless; again once
past midnight if the day has no value. First start 01:13: speed 33.14 ↓ 25.15 ↑ (36 s); the data check missed the
reply, which led to the router-sms fix (each look reloads the page); after it 23 s behind the scenes, 43 s visible.

## 18.10.2026, request 18 (v12)

> I'm confused why I always get a fresh web browser with these tests. I'm installing uBlock plugin not to see advertisement from speed test, and every time I run the speed test it looks like a new browser without any plugins. And I need to be forced to look at advertisement. Very bad also, you're using too much of my real estate. I told you next on the internet connection and remove internet. Understand it's internet just in parentheses. Put the test results. I don't need a new section, and I don't need the time when it was tested. I don't care about the time. I don't care

**Status:** built v12 18.10.2026: the speed test's Firefox keeps one profile (~/Library/Application Support/connection-keeper/firefox), so uBlock installed there once stays, behind the scenes too; the test result sits in parentheses after each live number, no item of its own, no time, no word "internet".

## 18.10.2026, request 19 (v12)

> also, I don't need text checked two minutes ago fall over. I don't need that's extra. Remove and reduce as much as possible size of this banner by reducing spaces. Also, 98.5 GB left. Nice, but time when we tested it's not important. Remove it please

> also, I don't need arrowsness to do speed because we're going to do color coding. Green number means download, red number means upload. That's all

**Status:** built v12 18.10.2026: no "checked … ago", no failover text (the status place shows only when it has something to say, the failover place only in the red alert), no time on the data ("98.5 GB left"), spacing 3 instead of 6, smaller margins; no arrows, download green, upload red.

## 18.10.2026, request 20 (v12)

> after this update, please push all the code to the repository. Now you can take the screenshot. We have two lines, line is never breaking. Please write that in manifest. We don't break lines in this application, one line only

**Status:** done 18.10.2026: the speed text is one line (no wrapping, clipped, its width measured on the widest text);
the rule is in MANTRA_MANIFEST modules/one-line-stripe.md; everything pushed.

## 18.10.2026, request 21 (v12)

> in the time of the run, you need to do all the tests, so speed test is happening, sms test is happening, only ping test is not happening. Also ping as soon as application start

> so when starting the new session, you put three dots for everything that is not pasted

> not tested

> trere doots inside parenthesis

> color: yellow
> color ping section yelloiw

**Status:** built v12 18.10.2026: at start the ping, the data and the speed test run at once (behind the scenes); until each answers its place says (...); the ping section is yellow.

## 18.10.2026, request 22 (v12)

> also for the device used for connecting to the network, every Wi-Fi device will be green. Every LAN port hardware port or maybe tethering through phone will be yellow. Green and yellow, so we are also doing the thing with network devices

**Status:** built v12 18.10.2026: the connection's name is green when the internet goes through Wi-Fi, yellow through anything else (LAN, USB adapter, phone tethering).

## 18.10.2026, request 23 (v12 bug)

> there must be some bug. I always see en0 as device, but I'm changing the devices. What is the n0? Why is the persistence

> please check the latest screenshot. This is the device under EM17. You should make its name available

**Status:** fixed v12 18.10.2026. en0 is macOS's own name for the Wi-Fi card. The keeper asked once, at its start, which
device is the Wi-Fi; at the login of 17.10.2026 23:40 the answer was empty and stayed so, and every connection was
shown by its raw device name. Now it asks every time (CoreWLAN first), and a device is shown by the name a person
knows: the Wi-Fi network's name ("mantra", or "Wi-Fi" when macOS hides it), any other device by its hardware port,
the name in System Settings → Network ("AX88179B" for the USB-C LAN on en17).

## 18.10.2026, request 24 (v12)

> App should check all internet connections and offer only the one which is online now. Offline doesn't make sense to offer. Make it live, real app please

> for test now, try to switch between LAN connection and Wi-Fi connection. I just connected to USB-C my LAN interface. There is a cable in, so it should also give internet

> or even better, when I confirm that what are actually my connection, they need to be graded out if they are not available

> yes, very nice. But at the same time I have also Wi-Fi enabled, which is right now what is active is Mantra. But also something needs to be grayed out because it's not available at this moment

> please see the latest screenshot. The section is missing "add lan interface meaning cable interface"

> besides the ping, you can also add the last test speed

> I'm talking about a small menu that opens the menu to change the connection

> open plese add to live connection in parentecis (LIVE) there was some other text not so clear what it menas this is clerar

**Status (request 24, all its parts):** built v12 18.10.2026. The drop-down lists his connections from ⚙ (Wi-Fi and,
new, LAN cable devices: "Add a LAN (cable) device…") and every other device with an address; each row is there at once
("checking…") and fills itself while open: "mantra (LIVE)   Wi-Fi · ping 28 ms · 23.1 28.6 Mbit/s" (download green,
upload red), "Something   Wi-Fi · not in range" greyed, "AX88179B   cable · ping 27 ms" yellow. A pick puts that
device first in macOS's service order (no password, proven: en17 above Wi-Fi). The keeper has a LAN driver, so a cable
in the list is a failover target. Speed tests are kept per connection. Seen by Marko (screenshots 01:47, 01:58); the
in-place rows after the cut/blank-bar fix not yet seen.

## 18.10.2026, request 25 (for the cloud session building the aggregation proxy, branch claude/dreamy-dirac-n94gqc)

> okay, then write the message to that session that it needs to ignore. If LAN and WiFi are coming from the same devices, these are not different devices. It needs to aggregate only devices which are different

**For the aggregation proxy:** aggregate only connections that leave the house through *different* devices. Measured on
this Mac on 18.10.2026: the cable (AX88179B, en17, 192.168.1.103) and the Wi-Fi ("mantra", en0, 192.168.1.102) both
go through the same TP-Link 4G router (192.168.1.1, one Telemach SIM), and each gives about 25–33 Mbit/s on
speedtest.net, the same line either way. Such a pair is one connection and must be ignored for aggregation. A way
to tell: the same gateway (router address and its MAC, `arp -n <gateway>` on each device) or the same public IP
(`curl --interface <device> https://api.ipify.org`) means the same uplink. A different uplink is, for example, a phone
on another SIM tethered over USB, or a Wi-Fi from another router.

Proven 18.10.2026 ~02:15: `curl --interface en0` and `curl --interface en17` both answer the same public IP, 86.33.86.202 (Telemach).

## 18.10.2026, request 26 (aggregation server, this Mac's session)

> please find a repository with this Swift app. We are doing it's called Connection Keeper and work on aggregating the devices. Now there are two devices online here in my home. My famous Wi-Fi from Nothing phone is called something, and there is TP-Link Wi-Fi which is called just mantra. They are both available here for you to test connections, test the speed, and see if individual speeds are actually faster with aggregation. Start to build aggregation server and everything needed for this to work

**Status:** v13 built 18.10.2026: ck-aggregate (SOCKS5 + HTTP on 127.0.0.1:8857, a connection per line, weighted by speed, the same line ignored), LaunchAgent, `test`. SOCKS, CONNECT and plain HTTP proven through it; the same-line rule proven (mantra Wi-Fi = cable). Waits for the Wi-Fi on Something to measure the two lines alone and joined.

## 18.10.2026, request 27 (the stripe: one line per connection + the aggregation line)

> now we will have user interface change, so when you connect to the new device you need to add one more line. I have two status lines for each individual connection, and at the bottom you need to add a third line which is status of the aggregation with speeds and everything. So I need to monitor everything separately. Three lines for now, if we have multiple, even more than two, then there are more lines

**Status:** v13 built 18.10.2026: a row per other connection (its own live speed, ping, joined or not) and the JOINED row at the bottom; seen on screen (AX88179B, mantra "same line", JOINED off).

## 18.10.2026, request 28 (the drop-down selects the connections to join)

> on the status line, it's basically the user dashboard. When the user opens the connection, he can select multiple connections or deselect them. If he deselects everything, then it means we are exiting aggregation mode

**Status:** v13 built 18.10.2026: JOIN tick boxes in the drop-down (the menu stays open), any tick turns aggregation on (macOS's SOCKS proxy → the server), none turns it off; the proxy switch proven without a password. Not yet ticked by Marko.

## 18.10.2026, request 29 (minimize, and back with Command-Tab)

> I did aggregate the This as you said joined. Give me minimize uh icon on the upper right corner so I can also minimize status if I need to And then when I switch to it with Any switcher like command tab, it should come up, it should not stay on the dock. So make that because usually things stay on the dock even if I switch to them. Then I need to go to the window and then I need to manually open them. That's very annoying behavior from macOS. I don't like this. We overwrite this. Minimize with mouse. Yeah. And then finding it with command tab and coming back to door position please.

**Status:** v13/v14 built 18.10.2026: "–" in the stripe's top-right corner hides it; the app is in Command-Tab and the Dock only while hidden; switching to it brings the stripe back to the same place and takes it out of the Dock again (proven through Accessibility: back at X 3016, Y 31). Marko's own Command-Tab not yet seen.

## 18.10.2026, request 30 (the stripe on the Mac display; a click on any row's speed tests it, the joined row too)

> I change the position of this window to be on the Mac display at the top. Take screenshots, and if something is cut off from the interface, please fix it   also, I want to have speed test when I click on the number for upload or download, same as with individuals, the same clicking applies to combinations so I can compare

> and you should compare now in this test phase

**Status:** built 18.10.2026: a click on a line's speed tests that line alone (down and up), a click on JOINED's tests every line and then all joined; the results in parentheses. The JOINED words fit (seen on the Mac display). Compared: cable 30.6/24.8, Something 40.0/18.9, joined 49.1 (+23%) down and 44.2 (+78%) up.

## 18.10.2026, request 31 (remember the last position and the last display)

> please make sure the app itself remembers its last position and its last display

**Status:** built 18.10.2026: the display by name and the top-left corner on it, saved on every move; a stripe partly off its display is nudged back inside THAT display. Proven: moved, restarted, came back to the same place on the Mac display.

## 18.10.2026, request 32 (the minimize button on the edge)

> also, minimus lion is in a strange position. It's not on the edge. Those kind of things are always on the edge

**Status:** built 18.10.2026: the "–" is pinned to the stripe's top-right corner, whatever the rows' width (seen).

## 18.10.2026, request 33 (a virtual network device: mantra_networkaggregate)

> now you need to create virtual LAN device, so in the macOS I can select this device and macOS will not know about aggregation. It will just use it as normal, and this device is doing aggregation. So I want to see in my status of connection where I'm connected to our aggregate, mantra_aggregate. It's called mantra_networkaggregate

**Status:** v14 built and installed 18.10.2026 (the free helper, `sudo ./tunnel.sh install` by Marko at 10:26): the stripe's first row reads mantra_networkaggregate; plain downloads with no proxy at 76.1 Mbit/s over both lines (new connections alternate 3/3 between the two public IPs); name lookups, UDP, the web, the keeper fine; the server killed: the device gone in 5 s, the web straight on the cable, back in 10 s when the server returned; ticks off: down in 2 s, on: up in 10 s.

> We can't pay. We can only do with free whatever we can do. So we go with free helper

(request 33, decided 18.10.2026: the free root helper with a utun device, no Apple developer account.)

## 18.10.2026, request 34 (after v14 no connections: one simple switch, aggregate or one connection)

> After you update, start to work on connection keeper. After the last update, I don't have any connections. I need to restart the whole computer. Something is wrong with this aggregation, something is blocked. So please make it simple to switch mode in the application to aggregate or one connection. To simply and quickly overwrite our aggregation services, so I can continue working.

**Status:** built 18.10.2026 (v15). The mode: one click on the stripe's last row switches ONE LINE ⇄ JOINED, and the drop-down starts with "One connection" / "Aggregate". One connection removes the helper's flag (utun99 down within 2 s), turns macOS's proxy off, stops the aggregation server and keeps it from starting at login (launchctl disable); the ticks are kept. Found: the tunnel-on flag was still there, so every restart brought the device back; at 12:17–12:19 the helper fought macOS, putting its routes back every 2.5 s; its only safety check was "does the server answer on 127.0.0.1", which stays true while nothing gets out. The helper (ck-tunnel) now sends a real request out through the device every 10 s (1.1.1.1 / 1.0.0.1, 4 s): two misses, or the routes vanishing five times in a minute, and the device comes down and rests five minutes. Proven: the stripe on ONE LINE, the mode file, the traffic check alone (true, 0.07 s). Not yet: the new ck-tunnel needs `sudo ./tunnel.sh install` by Marko; the click by his hand.

## 18.10.2026, request 35 (the words: one connection, aggregate connection)

> In the connection keeper application one line is not worded correctly. It should say one connection and  aggregate connection.

**Status:** done 18.10.2026 (v16): the stripe's last row says ONE CONNECTION or AGGREGATE CONNECTION (a click switches), the drop-down "One connection" / "Aggregate connection"; the name column made wide enough for the longer word. Seen on screen: ONE CONNECTION · click ONE CONNECTION to aggregate.

## 19.10.2026, request 36 (two USB connections combined: the LAN adapter and the Nothing phone's USB tethering)

> please let's work on my app connection keeper you need to start it and test it now I have two USB connection one is my USB to LAN adapter and connected to TP-Link another USB connection is my noting phone to A which is connected with USB tethering. So please detect and combine these two USB connections into one.

> Please make this switching from R and D I S mode to NCM. Automatically we are our connection app.

(request 36, added 19.10.2026: the keeper itself switches the phone's USB tethering from RNDIS to NCM.)

**Status:** built 19.10.2026 (v17). The Nothing A142's USB system refuses NCM ("Could not set unsupported function for the GadgetHal", tried with `tether_force_usb_functions=1` and `svc usb setFunctions ncm`; root would be needed), and macOS has no RNDIS driver, so the automatic RNDIS → NCM switch cannot be done on this phone; the phone's setting was put back. Instead the phone is a line over adb on the same USB cable: ck-phone (a small SOCKS5 server, Go, arm64) is pushed, started and forwarded by the keeper itself whenever a phone with USB debugging is plugged in; the stripe shows it as "Nothing A142 (USB)" and JOIN can tick it. Proven: the phone's own public IP 86.33.80.101 (the cable 86.33.93.191); alone 45.0 down / 22.3 up, the cable 19.5 / 12.5; joined through the server 10.0 + 22.9 = 32.9 Mbit/s (tele2/OVH, Hetzner answered 429); AGGREGATE CONNECTION switched on, the Mac on mantra_networkaggregate, the web fine, both rows "joined", 2 of 2 up. TCP only on the phone (adb carries no UDP): UDP stays on the cable.

## 19.10.2026, request 37 (USB in parentheses for the AX too)

> AX is also on USB, so you can add USB in parentheses as well.

**Status:** done 19.10.2026 (v18): a device whose network interface hangs under a USB device in the I/O registry is shown with "(USB)" on the stripe, in ▾ and in JOIN; the ticks and settings keep the plain name. Seen on screen: "AX88179B (USB)" and "Nothing A142 (USB)", both joined.

## 27.10.2026: onto the Mac's port registry (MANTRA_PORTS v2)

> please do rebuild and restart

**Status:** v19: ck-aggregate (TCP 8857, macOS's SOCKS proxy) writes itself into ~/.config/mantra-ports.json as its
owner once it listens. Rebuilt; not restarted, its LaunchAgent was not loaded.

## 28.10.2026, request 38 (the name, and the star)

> why don't I see Network Aggregate Application in my Star Menu Matrix, and rename it to Connection Aggregate Keeper so I can easily find it? Also, add Network in the name, so add everything so I can easily find it: Network Aggregate Connection Keeper

**Status:** done, 28.10.2026 (v20). The app is now /Applications/Network Aggregate Connection Keeper (Mantra).app
(bundle ids unchanged, so its permissions stay); the old Connection Keeper (Mantra).app (v19) is removed. Both LaunchAgent
plists point at the new path, and the aggregation server runs from it: v20, mantra + Nothing A142 (USB) joined,
mantra_networkaggregate up. A star row "netaggregate" in Mac (STAR_SWIFT rows.json), so the star, Swift Matrix and the
Star Menu's search find it under Network, Aggregate, Connection or Keeper.

## 28.10.2026, request 39 (WIRES or WI-FI: a switch that turns every radio off)

> please make a switch in my aggregate connection application. It should have a switch between wires or Wi-Fi. If I switch on the wire, there will be a toggle button right in the interface: wire or Wi-Fi. It will just use a wired connection. In this case, you need to test everything. Look, I have the same case, so that's why I need to switch I am afraid of Wi-Fi, and I think it burns my brain. I want this look. Now, right now, I have TP-Link, and I have Nothing Phone 2A. Both are connected at the same time through Wi-Fi and through the cable. This switch is choosing the cable and not using Wi-Fi, and even turning off the Wi-Fi on my computer. When I go to the cable, everything you can do: if you can switch off radios on everything. On TP-Link, if you can, through the web interface, switch off the Wi-Fi using only cables. On my computer, switch off the Wi-Fi using only cable. On my Nothing Phone 2A, if I'm sharing the phone as a wireless access point, you need to turn that off as well. So we go wires only, and my brain will be happy. Now everything is connected. Test it. Switch on, switch off, and see how it works.

**Status:** done 28.10.2026 (v21). WIRES | WI-FI on the stripe, the work in Tools/ck-wires; router-sms v3 got
`wifi on|off`. Tested from the terminal once each way, then three times from the stripe's own switch (pressed through
Accessibility): WIRES 45 s, 35 s, 35 s, WI-FI 37 s, 46 s; every radio read back off/on, the internet fine on the cable,
the API answering throughout. Two faults found and fixed on the way (the hotspot now comes back last so the Mac
rejoins mantra; only wired ticks stay). Left in WIRES, as he asked.

## 28.10.2026, request 40 (the colours of a connection)

> if not already, please color code my connection inside the app. Like this: Red means device is available, but it's not connected, green means device is connected, please change this in this app, and grey means it was connected in the past, but now it's not available

**Status:** done 28.10.2026 (v22). Seen on the stripe: AX88179B and Nothing A142 green, mantra grey (gone since
WIRES); with the phone unticked for 14 s it turned red ("not joined"), ticked again green. The ▾ menu uses the same
three colours (not looked at on screen: opening it needs his mouse).

## 28.10.2026, request 41 (one line: AGGREGATE CONNECTION with a small arrow)

> I am confused with this aggregate connection. Nothing, phone, mantra. I understand mantra was not there. Please make this clear in the user interface. Put only "Aggregate Connection" with a small arrow. I can open and see what is aggregated, and that's called the user interface. I see only Wi-Fi, aggregate connection, and then I click on it to see what is in that folder. I kind of understand. The whole status line is basically one line, not one, two, three, four lines. That's it

**Status:** done 28.10.2026 (v23). Seen closed: one line, "▸ AGGREGATE CONNECTION", 41.2 Mbit/s; opened: mantra
grey (not available, connected 22 min ago), AX88179B (USB) and Nothing A142 (USB) green, joined; closed again (68 px,
one line). Fixed on the way: the cable had no row of its own (it was the old first row) and showed grey.

## 28.10.2026, request 42 (the opened list: only what is connected now)

> please don't show past connections inside this main interface when I press this folder expansion button. Please just show what is actually right now connected, and that's all

**Status:** done 28.10.2026 (v24): opened, the list shows only the lines connected now (joined while aggregating,
else the one carrying the internet); mantra (gone) and lines merely here are not shown. Seen: AX88179B (USB) and
Nothing A142 (USB), both green, nothing else.

## 28.10.2026, request 43 (just "connection", smaller, WIRES/WI-FI under ⚙)

> also, aggregate connection is too much text. Just need "con." Just put "connection," and that's all. Nothing more. Then reduce the size of this thing Also, this switch between wires and Wi-Fi can go under the settings gear icon. It doesn't need to be visible all the time.

**Status:** done 28.10.2026 (v25). Seen: one line "● ⚙ ▸ connection | speed | ping | data", 1400 px wide where it
was about 2200. The ⚙ menu (WIRES / WI-FI / Settings…) could not be opened through Accessibility: Marko's click is
the test.

## 28.10.2026, request 44 (no empty space, resizable)

> now shorten the user interface so there is no extra space where there are non-numbers. There is empty space on the right side, and please also make this user interface resizable

**Status:** in work.

## 28.10.2026, request 45 (a grip on the right, the macOS minimize on the left)

> I don't need minimize button. We do it like this: On the right side, put the two vertical lines, which I'm dragging and resizing. When I drag left and right, I'm resizing the interface. On the left side, make a minimize button which looks exactly as minimize button from the macOS, and please align that button with the rest of the text, and that's the new interface. So we have this trick with these grabbing handles on the right side to resize and minimize with that icon from macOS. And that's it

**Status:** in work.

## 28.10.2026, request 46 (no LED)

> this green LED at the beginning of this application is not needed when the connection is green. I know it's a text connection. When it's red, I know it's not connected. Remove the LED next to the minimize circle

**Status:** in work.
