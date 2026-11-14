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

**Status:** done 28.10.2026 (v26): no fixed widths, no padding; 1544 px wide at 1×. Resizing done by the grip in v27.

## 28.10.2026, request 45 (a grip on the right, the macOS minimize on the left)

> I don't need minimize button. We do it like this: On the right side, put the two vertical lines, which I'm dragging and resizing. When I drag left and right, I'm resizing the interface. On the left side, make a minimize button which looks exactly as minimize button from the macOS, and please align that button with the rest of the text, and that's the new interface. So we have this trick with these grabbing handles on the right side to resize and minimize with that icon from macOS. And that's it

**Status:** done 28.10.2026 (v27): the grip ‖ on the right, the yellow macOS minimize on the left, in line with the
text. Seen at 1× and 1.4×; minimize pressed through Accessibility hid the stripe, opening the app brought it back.
The drag itself is for Marko's hand.

## 28.10.2026, request 46 (no LED)

> this green LED at the beginning of this application is not needed when the connection is green. I know it's a text connection. When it's red, I know it's not connected. Remove the LED next to the minimize circle

**Status:** done 28.10.2026 (v28): no dot on the stripe or on the opened rows; seen closed and open.

## 28.10.2026, request 47 (a digital display: nothing moves)

> all works. Only what is annoying me is when the text has more or less of the text. My user interface is breathing. It's changing the size. Right now it's changing the size. I don't know why some numbers are appearing, some are disappearing. Something is not here, right? Please make a digital display. Make fixed positions for every number and every letter, like in a digital display. Then everything is fixed. Now things are moving around, which is distracting

**Status:** done 28.10.2026 (v29): fixed slots for every field (speeds four places, tests six, ping, data, the status
slot always reserved). Measured 813 points in 20 readings over 20 s and 8 more while a pressed ping showed its status.

## 28.10.2026, request 48 (faster switching between the lines)

> yes, optimize speed of switching between lines. That's a good idea

(Asked after the cut test of 28.10.2026 morning: with mantra cut, every call timed out until a minute after it came
back; the server took 43 s to see the line dead and did not try the other line.)

**Status:** v31 built and measured 28.10.2026: the server sees a dead line in ~7 s (was 43 s), new connections race
to the next line after 1 s, names never hang; phone data cut 30 s: 44 of 44 connections answered. Found on the way:
in WIRES the system tunnel does not stay up (macOS removes its routes), so the Mac uses the cable alone; the fix is in
the root helper and needs Marko's password.

## 28.10.2026, request 49 (a rescan button: a plugged-in phone not picked up)

> for my aggregate application to aggregate multiple collection connections, how can I force it to recheck connections? Now it was on one. I plugged in my phone, and it's not automatically recognized. I want to have some kind of refresh or push button

**Status:** done 28.10.2026 (v32): ⟳ beside ⚙ rescans every device, phone and line ("2 LINES ✓ 22:37", 16 s), and a
plugged-in phone or cable is found within seconds and joined by itself (tested with adbd restarted on the phone: joined,
both lines alive 19 s later). The cause: the server leaked a pipe per program run and had been blind since 17:58 (no
line at all); fixed. The tunnel helper has the same leak, very likely why it "loses its routes"; installing the fix
needs Marko's admin password (`sudo ./tunnel.sh install`).

## 29.10.2026, request 50 (the phone over the cable by adb, automatically)

> The second thing: my connection aggregation app has a refresh button, which is great, but it doesn't work. It needs to use ADB to get internet from my phone. Now I have plugged in my Notion phone 2A. It has internet. I pressed refresh, and nothing is happening. It doesn't recognize it through the wire. Please make ADB code inside the app to share internet through the cable and disable any radios. As we said, if it's wired mode, please test the phone. The phone is connected, but it doesn't share its internet. Make it an automatic ADB system.

**Status:** done 29.10.2026 (v33, in the v34 build). The adb part was working (ck-phone answered with the phone's own IP
86.33.92.221); the server was not running at all: the Mac and the phone had restarted at 04:44, and macOS has both
LaunchAgents (keeper and server) marked "not allowed in the background" (Login Items), so neither loaded and ⟳ only
waited 30 s. Now the stripe loads them itself, at start, every minute and on ⟳. Tested: server unloaded → back in 57 s by
itself; unloaded again and ⟳ pressed → "2 lines alive" in 12 s. Radios all read off (Mac, TP-Link, phone hotspot).

## 29.10.2026, request 51 (a Wi-Fi icon on each line in WIRES: share it to the house for a while)

> wired mode. Next, each connection builds the icon, which looks like a Wi-Fi icon, which is grayed out or active, so I can overwrite it inside the mode of wires. Temporarily, I can enable Wi-Fi sharing of any active connection by that button, and it can temporarily become also going through Wi-Fi and through cable. Wi-Fi is never for this computer; it is for other devices on the network. Wi-Fi is never 5 GHz; it's always 2.4 GHz. Please now put me this icon. I can do on/off for the radio, of course, for our TP-Link, which is controlled through USB. Not through USB, it is controlled through Firefox and the web interface with a famous password. This is how you enable it, and for the Nothing Phone, you enable hotspot, and that's all. Now we can do it remotely with Nothing Phone ADB. AX88179B through Firefox interface. Please bring the Wi-Fi icon so I can quickly enable/disable for other devices in the house

**Status:** v34 29.10.2026: in WIRES every cable and phone row (open ▸) has a Wi-Fi icon at its left, grey off, green on,
amber switching. The cable's turns the TP-Link's 2.4 GHz radio on/off (router-sms, 23 s / 14 s), a phone's its hotspot
(adb, Quick Settings tile); the Mac's Wi-Fi stays off. Tested from the icon: AX88179B on (green, "WI-FI ON ✓"), off,
router read back off, internet fine. The phone's: not yet, it waits for its PIN after the restart (the stripe says so);
its band is read back after it comes on and a 5 GHz hotspot is reported red.

## 29.10.2026, request 52 (test the hotspot; no "show taps" on the phone)

> on the phone, hotspot is on. Please do the necessary testings. Please don't enable my tabs to see my tabs on the phone by default. I just turned it off, and it's now back on. I don't need these tabs, please

**Status:** done 29.10.2026 (v35). Show taps off on the phone and never switched on again (ck-wires no longer sets
show_touches). Tested: hotspot on 2427 MHz (2.4 GHz), sharing the mobile data, no auto-shutdown. From the stripe's
icon: off ✓ then on ✓ (2412 MHz, 2.4 GHz). Found on the way: "on" failed because uiautomator cannot read the Quick
Settings panel while it keeps redrawing ("could not get idle state", 11 s a try); now the tile is tapped where it was on
the last good read (phone-tiles.json), and if the hotspot does not change the same spot is tapped again to undo.

## 29.10.2026, request 53 (an icon in the menu bar with the live speeds; LED in the opened window)

> After you finish this, you need to make my app, which is aggregating connections, appear as an icon on the menu bar in my system. It also needs to show current upload and download speeds. When I click on the icon, the user interface opens, and it has one LED: green if the internet is connected, and red if it's disconnected.

**Status:** v36 29.10.2026: the network icon in the menu bar with the live internet speed, Mbit/s, download green and
upload red, fixed slots (seen changing: 1.5/0.5, 0.1/0.2); it turns red when the internet is gone. A click shows or
hides the stripe (remembered); the minimize circle now hides it to the icon. The one LED at the right end of the
stripe's first row, green / red (seen green). The click on the icon is Marko's to try.

## 29.10.2026, request 54 (the menu bar speed: copy the other app's look)

> for my aggregation application, please speed color. Take a screenshot of the menu bar, and you will see another app which is doing the counting. Please copy the same UI

**Status:** v37 29.10.2026: the other app is iStat Menus (network). Copied: a round dot, then two small lines, upload
on top and download below, "0.02 Mb/s", right aligned, the menu bar's own white; our dot is the LED (green connected,
red not). Compared side by side on screen. Ours reads lower: internet only (v10), iStat counts the house too.

## 30.10.2026: PERMISSIONS at the top right

> please make this in every application that needs some permission. If permissions are not set, it needs to have text in the top right: "Permissions." Then I click on it, and it opens me directly to my settings page where I need to set permissions.

**Status:** done in v38 (30.10.2026): the stripe has no ON / OFF row and no ⏻, so PERMISSIONS (amber #E8A33D, monospaced bold 12 like the stripe's words) sits at its right end, after the LED, left of the resize grip, while Accessibility (the only permission the stripe uses: joining a Wi-Fi through Control Centre, Join.swift) is off. A click asks once and opens Privacy_Accessibility. Re-read every 2 s; the stripe is refitted only when it changed. Nothing is asked by itself, at --login or ever. Built and installed; the stripe restarted quietly with --login (pid 730 → 41390). The keeper and ck-aggregate daemons were left running (v37 binaries, no change for them). The stripe is hidden in the menu bar (stripeHiddenInMenuBar), so the word was not seen on screen.

## 31.10.2026, request 55 (stress test every combination; the app once took the whole internet down)

> Please let's work on the aggregate connection now. My application. What is the issue? Last time this application bugged out the connection on my computer. I couldn't use any internet. So I flushed DNS cache and then that it was sold through application on my Mac called CleanMyMac. that's how I was doing it so there are some bugs in this application aggregate connections and now I have three connections addedSo please check all debugging phones and TP link and do stress test. Test all possible combinations of networks and don't disturb my connection with the server now. Mac must be on the Wi-Fi and this is also your network for talking with Claude and solving the problems. and use some other way of testing how to stress this this aggregation program to work with three connections one connections two connections any combinations and don't turn off Wi-Fi on TP-Link so we can continue working

**Status:** done 31.10.2026 (v39). The outage found and reproduced on a test copy (CK_AGG_PORT 8957), all seven
combinations (cable, Wi-Fi, phone, every mix): launchd's 256 open files; at ~125 connections every new one failed and the
server lost its lines. Fixed: 16384 files, 1500 clients, 15 s handshake deadline, true "active" counters, a phone on 4G its
own line. After: 250 at once 250/250, 124 held 20/20, 300 silent clients 10/10, failover 0 failures; 1000 at once is the
4G line's own limit (cable + phone 994/1000). Installed 09:58; the server restart cost ~7 s of internet. v40 (10:27): when no ticked line is present any line is used, and with only phones ticked the Mac's Wi-Fi carries UDP (0/10 → 10/10).

## 31.10.2026, request 56 (ON / OFF switch that cleans every trace, and TOP)

> Like we have in our manifest already, every application, including this one, has on-off switch, and off we going to clean up all traces from this app, and we have on top, which is just the word top. So please build this in the interface.We apply this rule to the Mantra sound recorder and read from that repository and do the same in this user interface.

**Status:** done 31.10.2026 (v39, Sources/App/OnOff.swift): ON OFF after the minimize circle, TOP before the LED. TOP
pressed through Accessibility: grey → green, the stripe from layer 0 to 25 (screenshots). OFF built (tunnel flag, proxy,
server and keeper stopped and disabled at login, ck-phone and adb forwards removed, passing files deleted; radios
untouched; a login start after OFF quits) but **not pressed**: it takes the tunnel away, waiting for Marko. The stripe was
hidden in the menu bar (stripeHiddenInMenuBar): unhidden and opened on the MacBook screen. OFF and ON pressed by Marko 10:20, both worked (OFF cleaned up in 2 s).

## 31.10.2026: the aggregate shows two connections, three phones are on the wire
> "Please check why my aggregate connection has only two connections. I have three connections at this moment. Three
> phones. Where is the third one? Why doesn't exist? Everything is on wire. And my nothing phone 7 is not registered in
> the app. What kind of app is that? It needs to check or ADB connected always, being ready for changes."

**Status:** looked at, 10:15: the Mac's USB has one phone (Nothing A142) and the AX88179B; no other phone enumerates
(system_profiler, ioreg). Ticked lines: Nothing A142 (USB), AX88179B, Google Pixel 7 (USB), Pixel 7 (wireless adb). The
Pixel's wireless adb went offline 09:09 and left 09:28 (the log); now no mDNS, no ping at 192.168.1.102. The app watches
USB and adb every second (deviceFingerprint) and logged every change; a phone not on the bus cannot be seen by any
program. Asked of Marko: replug the Pixel's cable, choose USB tethering / File transfer.
Found 10:18: the Pixel's own cable is charge-only (on the Nothing's cable the Pixel enumerated at once and the aggregate
joined it in 2 s, "Google Pixel 7 (USB): forwarded to 127.0.0.1:8860"). At 10:14 the AX88179B adapter was unplugged.
Left: a data cable for the Nothing, the AX88179B back in.

## 31.10.2026: the data left on every phone's SIM, by SMS
> "Please for aggregate connection you can send SMS messages from all these phones and check how much space is left on
> each SIM card. Please do that. If they have two SIM cards you need to detect TeleMach 1."

**Status:** done 31.10.2026: `Tools/sim-balance` (router through router-sms; every phone on USB: its Telemach SIM found in
`dumpsys isub`, STANJE sent to 13880 through Android's own SMS service, `service call isms 5`, which works on a locked
phone, the reply read with `content query`). First run: AX88179B (router) 88.9 GB, Nothing A142 (Telemach, SIM 2) 90.2 GB.
On the Nothing the Telemach SIM is in the second slot (bonbon in the first). Saved in Application Support/
connection-keeper/sim-balances.json. Every Claude Code session starts with `sim-balance --brief` (SessionStart hook,
added by the update-config skill): the saved figures if under 3 h old, else a fresh check (about 20 s).
Pixel 7 (Android 17, one SIM, Telemach): Android asked "Shell would like to send a message to 13880"; Marko allowed it
(remembered); then silent: 99.4 GB left (10:25). Android 16 (the Nothing) sends without asking.

> "Always at the start of the session check all connections free space on the sim cards how many gigabytes is left."

(Every start: the data left on every SIM of every line — the router's and each phone's — in GB.)

## 31.10.2026, request 57 (shorten the restart gap and the tunnel's step-aside time)

Marko, after the closing listed the two open times (~7 s after a restart, ~20 s for the tunnel to step aside): *"Can this time be improved?"* Then, to the plan (last lines remembered on disk, the Mac's own route while no line is known; the helper testing every 4 s with 2 s to answer, a 1-minute rest): *"Yes, please build."*

**Status:** done 31.10.2026, v41 + v42. Restart gap 6.2 s → 0.16 s (test copy), 0.38 s live (the lines remembered).
The tunnel steps aside in ~7–11 s instead of ~20 and rests a minute; v41's helper installed by Marko 13:28, it stepped
aside once for nothing (13:33, the Pixel's cable dropping mid-check), fixed in v42, whose helper waits for his password.

## 1.11.2026, request 58 (TEST SPEED / TEST HEALTH, and the Aggregate Download Monitor)

> for my aggregate services right now, the three phones connected basically are one router (TP-Link) and two phones, all on USB. Please, in the user interface at the top, are the buttons Test Speed and Test Health. It tests both things and gives a report in a pop-up window, reporting for each interface: - Speed - Speed together for uploading and downloading - Health You can also access different means using ping. There is an overall health graph, like speed and other things, which you think make sense for professional engineers in networking, in computer networking All three connections are here on 5G, so we are expecting around 150 or 200 Mbps. Please let's test it and let me know how it goes. If there are bugs, can this application aggregate downloads? Can my computer download fast? Can it stitch if it broke? I need you to take some 3D model, for example, a Whisper model online, which is around 1 gigabyte, and just break the connection and start the connection a few times. Keep Wi-Fi as a backup Wi-Fi mantra so you don't lose connection, and test all these features: connecting, continuing the broken download. Mani Svemir Whisper. Basically, you need to now connect my download monitor and my aggregate in one application. Down in the status line, it registers the file which is downloading. This is Aggregate Download Monitor. It registers the downloading file, and you can just press Resume if a download is broken. It gave verbose data about downloading status, speed, percentage, and estimated time of arrival. We do it on a real file from the Internet Whisper model.

**Status:** done 1.11.2026 (v43); see TAKEOVER 1.11.2026.

> please show me the user interface of this application

> I don't need a screenshot. I need to see it on the screen. Open it on the Mac

**Status:** done 1.11.2026 03:55: the stripe was hidden in the menu bar; shown again through its menu bar item (AX), on the MacBook screen.

## 1.11.2026, request 59 (MAC | AGGREGATE | BOTH, enterprise grade)

> please also give me the switch on the screen. It will be a two-grade output, basically. One is always green, and one is gray. It's a simple on-off switch we have on every app, which is going to allow me to switch between Mac connection or aggregate connection. Connection column: Mac, aggregate. I can switch between them. If I have my computer on Wi-Fi, I can just switch to Wi-Fi and ignore bypassing the aggregate. If I'm on aggregate, I'm bypassing the Wi-Fi of my computer or anything my computer does. It's either of these two connections that I can work with Third option is both. That means there is a fallback mechanism: if aggregate doesn't work, then local is working. It is fallback mechanism.Make this application enterprise-grade quality. Intelligent design makes it bug-free and with optimized code, and it works on the low level of the computer so it can work fast.

**Status:** done 1.11.2026 (v43); see TAKEOVER 1.11.2026.

> both phones are on ADB. Take a screenshot. They are on 5G. Don't make nonsense claims. Android, not 5G. What is this? You can control my phone and confirm what's there. Set it up and make it fit

**Status:** confirmed 1.11.2026 04:02: both data SIMs show 5G NSA (TelephonyDisplayInfo overrideNetwork=NR_NSA; the Nothing's data on SIM 2 Telemach, the Pixel's on SIM 1). ck-net read the LTE anchor (gsm.network.type) and the wrong SIM's signal on the Nothing: now it reads the data SIM's own block, as the status bar does.

## 1.11.2026, request 60 (4G / 5G buttons per phone)

> find algorithms which can, through ADB, quickly first of all check what's there. Also, I want to have, next to each Wi-Fi connection, a Wi-Fi icon. I want to have icons for any device supporting it. A phone is for sure 5G or 4G, so I can remotely, through ADB, switch my quality of connection please make two buttons next to the Wi-Fi icon, 4G and 5G, and I can remotely change that on my phone

**Status:** done 1.11.2026 (v43); see TAKEOVER 1.11.2026.

> please read me in voice. What is left to do for this aggregate service? Is anything left to do? Where are we now with the project? I don't have 5G or 4G. I told you at the beginning of line. When there is a Wi-Fi at the beginning of line, the switcher: please move the buttons

**Status:** done 1.11.2026 04:20: read by voice; 4G 5G at the beginning of the line, left of the Wi-Fi icon (seen on the stripe).

> please fix my user interface. You need to put "Test", then "Column", and then "Speed Health". Not two times: "Test Speed Test Health". Between "Test", "Speed", and "Health", you need to put a pipe

**Status:** done 1.11.2026 04:20: `TEST: SPEED | HEALTH` on the stripe (seen).

## 1.11.2026, request 61 (4G / 5G tested; a speed test at every start in the bottom line; ✕ on every status line)

> please test switching between 5G and 4G. Is it working? Always, at the end, at the starting, not at the end, at the starting of the app, you need to do a speed test, and that speed test is displayed in the status line at the bottom of the app

> at the next to each status line, put a small gray X at the end so I can close the status line. It's not stuck on the screen forever

**Status:** done 1.11.2026 04:26: 4G ↔ 5G tested on both phones (NR_NSA → LTE_CA → NR_NSA); the quick test at every start (04:25: ↓ 293 ↑ 331 Mbit/s all lines together) in the bottom line; ✕ pressed, the line closed.

> write in the manifested note that pipe is there to divide options, so there is. With that rule, it's not possible that before test pipe appears, so remove it before test text

**Status:** done 1.11.2026: no pipe before `TEST:`; the rule written in MANTRA_MANIFEST modules/one-line-stripe.md.

## 1.11.2026, request 62 (separator lines, the Nothing's 4G/5G, hover on every button)

> Tunnel is installed now. First of all, in the user interface, I need horizontal lines to see separate parts of the interface. Under the first line, put the horizontal line. Then all my connections are coming, and then another horizontal line for status. I'm not able to remotely switch between 5G and 4G. On Nothing Phone, Google works. Nothing Phone doesn't work. Please make it work I need to have a hover over. When I'm under any button, it's changing color. It becomes much more. I don't know how to find the way. Something so I know I'm over that, and when I click, it's going to react.

**Status:** done 1.11.2026 (v44): two thin lines (under the first row, above the status lines), seen; 4G / 5G are items of the row now (inside the lead they stood partly outside it: his clicks on the Nothing never arrived), his press on the Nothing's 4G at 04:33:31 arrived and the phone went to LTE_CA in 9 s; every button gets a light plate and the pointing hand on hover and a green flash on a press (Hover.swift). The tunnel helper v43 installed by Marko (version 43, state on utun99).

## 1.11.2026, request 63 (hover: enlarge the buttons and their click area)

> please build in hover over so I know where are the buttons which can be pressed. The most maybe easy way is just to enlarge its buttons so even its area of clicking is enlarging

**Status:** built 1.11.2026 (v45): under the mouse a button grows by a quarter about its centre, a brighter plate (26 %) with a white rim, the pointing hand; every button's click area at least 8 points wider than its word and 22 high. The layout seen unchanged in a screenshot; the hover itself only Marko's mouse can show.

## 1.11.2026, request 64 (the speed test window: no Firefox interface, only the close button; uBlock Origin inside)

> please, we are working on my adblock connection application. We need to fix the opening of the Firefox window. First of all, you need to open it without any user interface parts. Only X will be there to close the test. Second of all, you need to load this application in the Firefox window. When it opens, you block the extension. It is working in my normal Firefox. I installed it, but I don't know why this window is opening in its own special Firefox without any of my settings. You block is blocking commercials, which are on this speed test site. I don't want to see commercials. Use uBlock to block it. Please now build this upgrade for speed test. When I test speed, when I click on the number

**Status:** done 1.11.2026 (speedtest-firefox v46): the window has no tabs, address bar or toolbars, only the macOS title bar with its close button (userChrome.css, seen in a screenshot); his own uBlock Origin 1.75.0 is copied from his Firefox profile into the test's profile at every start (a newer one he installs comes along). Seen: speedtest.net with 0 ad frames (before: 11, Google and Amazon ads). The first start after the copy still showed ads while uBlock loaded its lists; from the second start on, clean.

## 1.11.2026, request 65 (Claude Code's connection drops: detected, shown in the status line, protected against)

> this application can also test as debugging for Claude code, because Claude code usually gets some drops, and then it gets me API errors or messages that it cannot reach the server. This is a momentary drop in connection. In the status line, you need to detect that the connection dropped with Claude Code locally, and then slowly understand why this is happening and build some kind of protection for these drops. You need to write this in the manifest, so every session runs this mod. You need to create a mod for Claude Code which is going to detect drops of connection with the API, and then you need to please mark this inside the status line of the aggregate connection and work on solutions

**Status:** first part built 1.11.2026 (v46): `ck-claude` (Tools/, in the app's Resources, on the PATH) follows every Claude Code transcript, writes each failed try with a snapshot of the lines (mode, tunnel, route, DNS, a real TLS handshake) and probes the API every 30 s; the stripe's bottom row `☁ CLAUDE` (seen, docs/v46-claude-row.png); the mod `api-drops` (mods/api-drops, validated, types checked) for the status line of every session; the rule in MANTRA_MANIFEST modules/claude-api-drops.md. Found: 13 episodes in 7 days, 10 of them EPROTO; the 30.10 outage was DNS (4 h); an 87 s gap at the restart of the app (the aggregate kept running: cause open). Seen live 1.11.2026 05:57 in this session's status line: `api-drops: ☁ API ✓ 81 ms` (screenshot). Marko 06:00 "all the time": `CLAUDE_CODE_PLUGIN_DIRS` added to the env block of ~/.claude/settings.json; `claude plugin list` shows api-drops@inline from mods/api-drops, ✔ loaded, for every new session.

## 1.11.2026, request 66 (a download uses only mantra; the Pixel 7 on 5G does nothing: debug the load distribution)

> Please, now it's time to monitor aggregate. My aggregation app is downloading the file from the internet. I have two connections, Mantra and Google Pixel 7. Google Pixel 7, in the middle of transfer, I switch to 5G. I am sure it can go up to 70 megabits per second or something like this, but this connection is not used at all. So please this load distribution and using the speed of both connections or three connections, whatever, please build it professionally. This is amateurish work. Everything going through mantra, a Pixel 7 which is fast is not doing anything. Which is very strange. Please debug this application.

**Status:** done 1.11.2026 (v47, Balance.swift). **Found:** the server chose a line by connections ÷ the stored speed test, keyed by public IP; the Pixel's 5G address had never been tested, so it counted as 10 Mbit/s for five hours, mantra as 36. Measured alone at 10:50: Pixel 5G 128–140 Mbit/s, Pixel 4G 39.5, mantra 12.6–25 (busy with the Chrome download). So the heavy connections went to the slowest line: 1,944 MB over mantra, 263 over the Pixel. 4G ↔ 5G on the phone itself is logical (~1 s, same public IP, stays joined); the server was not: 10 Mbit/s either way. **Built:** every line's live rate each second, its recent peak (half-life ~10 min), a 3 s probe when a line has no known speed, when a phone's radio changes (6 s after the switch, again 30 s later) or its public IP changes; a new connection goes to the line with the lowest (rate + 2 per busy connection) ÷ capacity. **Proven:** test copy 4G → capacity 38, 5G → 139 within ~15 s; joined 179 Mbit/s (Pixel 382 MB, mantra 73); live through the tunnel 117.6 Mbit/s (Pixel 127 MB, mantra 36); server restart gap 0.3 s, done after the Chrome download had finished (10:50), so it was not cut. **Not possible:** moving a connection that is already open to another line (that needs a bonding server of ours on the far side, a VPS); one big download spreads over the lines only when it opens several connections: ck-net, or Chrome's chrome://flags/#enable-parallel-downloading.

## 1.11.2026, request 67 (5G only for big downloads: after 5 minutes of fast downloading, back to 4G when it ends; close the session)

> Please.Close this session, write in the manifest everything what was learned, all the lessons, and before quitting switch my phone to 4G. So, there should be also one more feature before you go. If I'm downloading huge files, you need to switch all my phones to 5G, but only after 5 minutes of downloading. and when fast download is finished when big download is finished you need to bring it back to 4G and now before quitting build this feature test it and bring my phones to 4G this should be 5G is only used after five minutes of constant downloading at the high speed then it speeds up and when the speed drops after five minutes you go back to 4G

**Status:** done 1.11.2026 (v48, Sources/Aggregate/Boost.swift): the phones rest on 4G; all lines together ≥ 15 Mbit/s down for 5 minutes without a break → every phone to 5G; < 5 Mbit/s for 5 minutes → back to 4G; the state in boost.json. Tested on the test copy with 40/30 s windows: 4G → 5G at 11:14:40 after 40 s at 84 Mbit/s (the Pixel then 123 Mbit/s), back to 4G at 11:15:47 after 30 s quiet. Installed 11:18 (gap 0.2 s, no download running). The Pixel left on 4G (LTE CA); the Nothing is not plugged in (on 4G since his press at 04:33). Lessons in MANTRA_MANIFEST modules/network-aggregation.md and lessons-learned.md.

## 1.11.2026, request 68 (the stripe must not follow him to every desktop and display)

> Please make my application not follow me everywhere. If it's open on one screen, it needs to stay there. I don't know what's going on. When I switch desktops, monitors, it's following me all around.

**Status:** done 1.11.2026 (v48): `.canJoinAllSpaces` taken off the stripe in both TOP modes (`.managed` now); a click on the menu bar icon still brings it to his desktop (`.moveToActiveSpace` for half a second). Installed; Marko confirmed 1.11.2026: "now the stripe stay put". He also switched on Chrome's parallel downloading.

## 2.11.2026, evening
- Marko: "when you start to upload things to the drive, switch both phones to 5G to speed up", then "make a rule for uploading and downloading. Momentarily put it at 5G. When it's over, you need to bring it back to 4G ... It's burning my brain, and there's no need because there is no action on the internet." **Status:** done: Tools/phones5g (on / off / status / during CMD, a shared count so 4G comes only after the last transfer), on PATH; emupload copy uses it

## 13.11.2026, request 69 (WI-FI / CABLE / BOTH check marks, line lists, dead-SIM fallback, signal strength)

> I have now connected through the cable and dongle. The AX88179B USB LAN cable is going from TP-Link. ... I wanted to have an action button at the top to control the connection. There are three options, actually. If I have check marks, I do my options. So just put check marks at the top. What I want to use: - Wi-Fi: if I click that, Wi-Fi is enabled in the system. - Cable: if I click that, cable is enabled in the system. - Both: if I click both, aggregation works with both. If I click on Wi-Fi or Wired, I have a list of all wired and Wi-Fi connections currently available, and I can check mark which I want to use. ... Is it possible that my TP-Link connects to this Wi-Fi of my phone, and then through the cable, it brings internet to my computer? ... The SIM died. ... How to make a fallback? If it's connected, it doesn't have any data throughput, and I have Wi-Fi. It needs to understand that there is no data. It needs not to fight with it. It needs to ignore it ... in that sense, I want to see signal strength in my user interface for anything connected to my computer that's giving some kind of internet

**Status:** research 13.11.2026: the TL-MR110-Outdoor has only "3G/4G Router" and "Wireless Router" (Ethernet WAN) modes, no WISP, so it cannot take the phone's Wi-Fi as its uplink; the Mac joins the phone's hotspot "Something" directly instead. Quick fix 13.11.2026: Wi-Fi put above AX88179B in the service order (no password needed), GitHub 1.6 s afterwards. **Built 13.11.2026 (v49):** top row WI-FI / CABLE / BOTH tick boxes (Choose.swift; the word WI-FI lists the networks in range, CABLE the wired interfaces and phones, with ticks); the order through `networksetup -ordernetworkservices`; BOTH = the existing aggregation over the ticked lines. NO DATA fallback (Health.swift): an HTTPS probe through each line every 20 s, two failures = amber NO DATA, last in the service order, out of the aggregation (Aggregation.dead, read by ck-aggregate), back after a minute of good probes, every switch in the log. Signal: see request 71.

## 13.11.2026, request 70 (traffic lights on the left)

> fix the user interface of this application. On the left side, like any window in the Mac OS, I need to have a red button, a yellow button, and a green button. Same here, only on the left side. Now I have one yellow on the left and one green on the right, which is a disaster

**Status:** built 13.11.2026 (v49, Lights.swift): the real standard buttons (NSWindow.standardWindowButton) red / yellow / green on the left of the top row, 20 pt apart; red closes the stripe (hidden, menu bar icon brings it back, nothing stopped), yellow hides it to the menu bar as before, green toggles full width and back. Settings and Tests windows have all three (miniaturizable + resizable added to Settings). Not seen on screen yet: only the GitHub run checks the build; whether the buttons draw coloured while the panel is not the key window is open.

## 13.11.2026, request 71 (precision signal meters, like a VU meter)

> for Wi-Fi connections, I need precision signal measuring, professional ones, like a VU meter on the audio equipment that precise I need to install some Android application on my phone to make these readings 100% accurate. We can do that as well that phone is accessible over tail scale, so you can edit, beat, and install anything on it. It's yours that's nothing fun, which is now saving my ass

**Status:** 13.11.2026: the Nothing A142 on the roof reached over adb through its own hotspot (10.146.4.205:5555; Tailscale down). Live: LTE RSRP −98 dBm, RSRQ −9 dB, SNR 6 dB, level 3. No app needed for the values (the modem gives them to dumpsys exactly as to any app). VU-style meters with peak hold and a large meter window added to the v49 build.

**Built 13.11.2026 (v49, Signal.swift):** a VU meter in every line row (zones red/amber/green, live value every 1 s, peak hold falling 1 % of the scale a second, the exact number and 4G/5G beside it); a click opens a resizable window (traffic lights on the left) with all values and a 5-minute graph. Mac Wi-Fi from CoreWLAN every 1 s (RSSI, noise, SNR, tx rate, channel, band; Location permission shown as PERMISSIONS when the reading is 0); phones one adb shell every 2 s (LTE rsrp/rsrq/rssnr/rssi, NR ssRsrp/ssRsrq/ssSinr); the phone whose hotspot the Wi-Fi is on is reached at its gateway :5555; the cable shows its link speed. Not done: the TP-Link's 4G signal, an on-phone meter app, Tailscale address (gateway only).

**v50 (13.11.2026):** after seeing v49: drawn coloured traffic lights, neutral cable meter, two meters (WI-FI and 4G with SINR) on a hotspot line, duplicate MAC/AGGREGATE/BOTH words removed.

## 13.11.2026, request 72 (compact meters, narrower stripe, what is the CLAUDE row)

> now this user interface is becoming too long with these meters. We need to reduce it. Both meters need to be parallel, one atop the other, and there's too much text: phone to tower, MAC to phone. Wow, it's too much. You just need to make some kind of icons. You just make 4G and Wi-Fi only. What is in parentheses is now main text, and things can be reduced because they are now in parallel. You can make half size of this line. It's too thick. This meter can be half size. Please do that and reduce the width of my application. That is Claude doing something inside. I don't know what it is doing and why I'm using the Claude API here. What is its role inside this application? I don't see anywhere where I can check.

**Status:** v51 in progress: stacked half-height meters with 4G / Wi-Fi icons, a narrower stripe, the CLAUDE row folded into one cloud icon with a plain tooltip, the API probe every 120 s instead of 30.

**v51 (13.11.2026):** compact stripe: stacked thin meters with 4G/Wi-Fi-symbol tags, one number per direction, compact info words, test words as icons, Claude row replaced by a cloud icon (probe 120 s, switch in Settings).

## 13.11.2026, request 72 (a Tailscale guard that never sleeps)

> I don't want this thing to happen with Tailscale anymore. Can we also build some demons which are always active and controlling Tailscale? If I'm in the USA and I want to access my computer, and Tailscale is because it's all day awake and tired ... this demon is restarting it automatically, refreshing it

**Status:** built 13.11.2026 (v52): the guard in connection-keeperd (TailscaleGuard.swift): `Tailscale status --json` every 60 s; a broken one (coordination server in Health, not Running, Self offline, every peer rx 0 and a ping failing; two checks in a row, internet working) is healed with `scutil --nc stop/start "Tailscale"`; back-off 2/5/15 min, 6 restarts an hour at most; also checked 15 s after a default-route change and after a wake; never signs out or changes settings; log lines TAILSCALE in connection-keeper.log; the icon on the stripe's top row. Cause today: the extension came up while the default route was the dead SIM cable.

## 13.11.2026, request 73 (a phone joins the pool only with its own uplink)

> It registered that pixel is connected with the cable, and it put it in the pool of connections. But if you look at my pixel, it's in airplane mode and is using a connection already existing in the network over Wi-Fi. This aggregation is total nonsense. Please make my application more intelligent, not to share these kinds of connections

**Status:** built 13.11.2026 (v53): `Phones.uplink` (one adb shell: airplane_mode_on, mobile_data, Wi-Fi state, transports of the default network in dumpsys connectivity); in ck-aggregate's discover a phone with AIRPLANE, VIA WI-FI or DATA OFF stays out of the pool, a phone with the same public address is SAME UPLINK; each is logged on change, shown in the ▾ and CABLE lists greyed with that word, and joins by itself at the next look (every minute) when it has its own uplink again. Measured before: the Pixel 7 had airplane_mode_on 1 and sat on "Something", the Mac's own Wi-Fi line.

## 13.11.2026, request 74 (two tabs: ALL and IN USE)

> we need to make this connection keeper again clearer to understand the problem. Now there are so many connections, some of which are here like this Wi-Fi looping, blah blah. I want to have a very simple user interface, a very simple one. I have two tabs. There will be all connections on the first tab, and the second tab will be connections in use. I can see everything which phone can see, and then I can see what is actually in use.

**Status:** built 13.11.2026 (v54, Tabs.swift): tabs ALL / IN USE centred under the second row; IN USE default.

**v55 (13.11.2026):** fixed the launch crash of v54 (tab spacer constraint activated before the views had a common ancestor); `--selftest` flag and a CI step that runs it.

## 13.11.2026, request 75 (the menu bar item, always, beside iStat)

> please put My Connection Keeper Always Available in the menu bar. Make it start by system and let it be there, always positioned next to this ISTAT. They need to be next to each other; they are partners.

**Status:** built 13.11.2026 (v55, MenuBar.swift MenuBarPlace): login item through SMAppService.mainApp at every start; the status item has the autosave name ConnectionKeeperItem and its preferred position (display width minus iStat network item's left edge) is written to our own defaults before the item is made, checked 3 s after start and after a display change, remade when more than 8 pt from iStat. iStat's preferences are never written.

**v56 (13.11.2026):** menu bar placement measured: the preferred-position key cannot put the item beside iStat (see MenuBar.swift); the recreate loop is gone, one log line; a Cmd-drag by hand places it and macOS keeps it.

## 14.11.2026, request 76 (the speedometer opens speedtest.net in the app's own browser, ads blocked)

> for connection keeper The icon on the right side is one, two, three, four, an icon that looks like a speed meter. It needs to do a different action. Remove whatever is doing now. And it needs to open up. In its own browser, so the browser must be encoded in this application. You find the lightweight mini web browser, an open-source Chromium on GitHub. https://www.speedtest.net/ This is the site it needs to open, and it must have already built-in the plugin to block commercials. ublock And it will open up in this window. Please update my application.

**Status:** built 14.11.2026 (v57, SpeedBrowser.swift): the speedometer icon no longer runs the line test; it opens speedtest.net in a window of the app itself (WebKit, the Mac's own engine: Chromium/CEF would add ~250 MB to every release over a SIM line with no data left). Ads: uBlock Origin's default lists (uBlock filters, privacy, unbreak, EasyList, EasyPrivacy, Peter Lowe's) converted to WebKit content rules on GitHub's runner (Tools/make_adblock.py, checked by Tools/check_adblock.swift), plus a hand-written seed list of 69 ad networks that always loads; the page loads only after the rules are in. Back / reload / home and the rule count on a thin bar at the bottom.

## 14.11.2026, request 77 (only the test frame on speedtest.net)

> There are no ads at all, but there are extra interface elements. Can you remove them? I need only: Go, Download, Upload speeds, This pink line, Telemach, This part only. Can we have only that frame and remove Sign In and all the other nonsense?

**Status:** built 14.11.2026 (v58): Resources/speedtest/frame.js, injected at document start: everything outside the column .pure-u-custom-speedtest hidden (header with Sign In, menu, Download, footer), in the column the cards from #content-card-stack down hidden, in the frame the RESULTS · SETTINGS tabs and Connections row hidden; a MutationObserver keeps it so while the page changes. The privacy box stays answerable. Window 820 × 600; an eye on the bottom bar shows the whole page. Checked before the build in headless Firefox: only GO and the Telemach / server part. The frame during and after a test not seen yet (no test run on the SIM).

## 14.11.2026, request 78 (the browser without edges, only the middle frame)

> Please make a browser without any edges, only showing the middle frame. That's all. Look at the screenshot right now I don't want to have any margin, just useful information on screen.

**Status:** built 14.11.2026 (v59): borderless window (no title bar, no bottom bar, rounded corners); frame.js measures the frame (every visible thing in the speed test column put together), shifts the page with a transform so the frame starts at a 12 pt edge, and posts its size; the window takes exactly that size. Share, Result ID and the boxes under the result hidden. Esc closes, Cmd-drag moves, Cmd-R reloads, the speedometer again closes. Checked in headless Firefox on the start page (404 × 315) and a result page (504 × 294).

## 14.11.2026, request 79 (the grip closes the gaps before the letters shrink)

> Also fix the resizing algorithm for this app. I have a gripper on the right side. Before actually changing the font size, you need to first remove the gap between the text. The text is compressing, and then the window is resizing.

**Status:** built 14.11.2026 (v59): `gap` (0…1, saved as stripeGap) scales every stack's spacing and side margins; a drag narrower first lowers the gap to 0 at the same letter size, only then the scale goes down; wider: the gap back to 1 first, then the scale up.

## 14.11.2026, request 80 (IN USE / ALL: click a name to join it, white/green, LAN and Wi-Fi filters; QC of the aggregation)

> Please go to the window "In Use" and on. I need a little bit of update. In "In Use" under All, now a new connection has appeared. Which is nothing over USB. When I click on nothing over USB, it is now white. When I click on the name, it should become green and become part of the aggregated connections. Also, when I'm in All, you need to make filters. One is LAN. Next to All is a line that's grayed out. If I select it, only LAN connections are shown, and LAN connections by LAN connection. I mean everything wired, so nothing over USB will also be shown.
>
> Then there's another icon, the Wi-Fi icon, which is grayed out. If I press the Wi-Fi icon, it becomes green and shows me only Wi-Fi. In this case, it will show only Mantra. And again, repeating that is the name of the connection. It is green or red. That's the toggle. When it's red, it's not in use. When it's green, it's in use. Instead of red and green, better make it white and green. White means it's not in use. I click. Green means it's in use. Now I have two connections there. Test all the new features, and please test the speed and see if something can be improved. Is the aggregation algorithm the best in class, or are there some other GitHub repositories showing better algorithms? Please compare with some other competition.
>
> It's working, and what works better with the parameters of the aggregate connection? I don't know which are there, but you need to find some kind of speed, bare loading, and whatever is there. Read some books on how to get the aggregate connection and what the parameters are, which is like a QC quality check of the software.
> Also browser window icon or speed icon for this speed net should be also opening and closing that window. Doglink, and I don't need any status line, also not the title line. I just need this speed to be the size of the UI of Speed Net, and that's all. The button in the interface of Connection Keeper is closing it and opening it.

**Status:** built 14.11.2026 (v60, Tabs.swift): in ALL a click on a line's name ticks it into the aggregation (green) or out (white); the first tick switches aggregation on with the Mac's own line ticked too; a line with SAME UPLINK or no internet says why it cannot join. Two filter icons beside ALL (LAN: cables and phones over USB; Wi-Fi), grey off, green on, again = everything, one at a time. The speed window is v59. Aggregation QC: see TAKEOVER (research 14.11.2026). The speed window part is v59 (borderless, sized to the frame, the icon opens and closes it).

## 14.11.2026, request 81 (nice arrows by the speeds)

> Just to improve the user interface, next to upload speed, make a nice up arrow. Next to the download speed, make a nice download arrow.

**Status:** built 14.11.2026 (v60): SF Symbol arrows (↓ green, ↑ red) before each speed number, on the first row and every line row.

## 14.11.2026, request 82 (H: help as an infographic in the app's own browser)

> Add one more icon next to the top and close to this test health, which is H. That's the help. It is kind of infographics explaining all the parts of the user interface, and it is using the same ASP test, same browser, to show itself. I can read about the app there, but infographics is the most important thing. So quickly, I can see what each icon does and how to use this app.

**Status:** built 14.11.2026 (v60): H (question-mark icon) after HEALTH; Resources/help/index.html, a numbered drawing of the stripe with a card per part, the colours, four steps to faster internet; shown in the same edgeless WebKit window, H again or Esc closes.

**Tested 14.11.2026 (v61):** filters, join by click, arrows, help, speed window open/close: all seen working on the Mac. See TAKEOVER for the aggregation QC.

## 14.11.2026, request 83 (build the aggregation improvements, order mine)

> improvements, building order. It's up to you. Just update it

**Status:** built and tested 14.11.2026 (v62–v64). 4: health loop 1 s, both answer points at once, a failed real connection checks its line at once: a pulled cable out in 1.1 s, a quiet line in 3.9 s (was ~6 s both; test copy with the fault switch). 3: connect time smoothed per line, + rtt/1000 in the line choice; live 102 ms AX88179B, 85 ms Nothing. 1+2: ck-net end-game: a free connection takes the end of a running piece, split by the two speeds (pieces shrink to fit each line at the end); seen twice in a 105 MB test (11.8 Mbit/s, the file intact). v64: HTTP 429 rests a line 15 s. v63: asks to update at start (kits/mac-updater). 5 (bonding through chromium-vm): not built; a day's work, next.

## 14.11.2026, request 84 (improvement 5: bonding through the Oracle Cloud server)

> start to work on this improvement: 5, through bonding to Oracle Cloud Server. Take a day of work to do it now explain to me how we are using my cloud server for the bonding. What is the workflow? What is the reason to do that

**Status:** explained 14.11.2026; facts: chromium-vm is eu-frankfurt-1, VM.Standard.A1.Flex 2 OCPU / 12 GB, 2 Gbit/s, public 130.61.181.83, ~35 ms from the cable and the Wi-Fi; only SSH (22) open to the internet. Marko said yes to port 443. Checked by the oci CLI (14.11.2026): the subnet's Default Security List for teacher-vcn already lets in TCP 22, 80 and 443 from anywhere, and the VM's iptables INPUT policy is ACCEPT: no console step needed. Oracle sign-in user: marko.bosko@auroville.community; the server's tenancy: markoboskoauroville. An Opus worker writes ckbond (client + Go server, CI loopback test).

**14.11.2026:** Marko: "I'm giving you yes right now" — yes to install the ckbond server on chromium-vm (port 443, systemd, token in /etc/ckbond).

**Status 14.11.2026 (v65–v66):** ckbond v1 built (docs/ckbond.md): Go relay (release asset ck-bond-server-linux-arm64, Tools/bond/install.sh + ckbond.service), Mac client in ck-aggregate (off until bond.json says on). Proven on GitHub's runner only: one stream 105.6 Mbit/s over emulated 80 + 80 + 16 Mbit/s lines, intact after a line went silent mid-fetch (run 43565043618). Not yet: relay installed on chromium-vm, bond.json on the Mac, a test over the real lines; UDP is phase 2.

**14.11.2026 07:18 live:** v66 installed on the Mac, bond-init, relay on chromium-vm (install.sh: "ckbond: active on :443"), bond on: leg AX88179B up (rtt 40 ms), public address 130.61.181.83. Found: page loads 0.6–1.4 s through the bond vs 0.33 s direct, and only one line in the pool (the Nothing went VIA WI-FI). Bond set off at 07:22; the worker fixes the delay and makes bond step aside with fewer than two lines.

**14.11.2026 07:28 live, two lines (Nothing Wi-Fi off):** 10 MB single stream: direct 51 Mbit/s; bonded 40 Mbit/s (AX88179B 1.35 MB, Nothing 9.2 MB; both legs show rateMbps 10: the rate estimate does not learn). Pages through the bond 0.25-0.30 s. Bond off again; the worker fixes the estimator.

**Status 14.11.2026 (v67–v68):** after the first live test: rate estimator fixed (the phone's bursts), optimistic OPEN, bond steps aside below two lines (`bond.bypass`), relay rate visible in /status. CI v68: 96.3 Mbit/s one stream over 80 + 80 + 16, intact after a line died. Waiting: v68 on the Mac and the v68 relay on chromium-vm, then the live 10 MB comparison again.

**14.11.2026 07:50 live v68 (Mac + relay), AX88179B + Nothing:** 10 MB one stream, three runs each: direct 17.0 s / 2.25 s / 26.1 s (two stalls); bonded 12.6 s / 2.18 s / 2.81 s; pages through the bond 0.23-0.36 s; bypass null (both legs). Relay estimates after: AX88179B 4.1 Mbit/s (looks too low, it carried 6 MB), Nothing 31.5 (25 MB); the Nothing rtt 385 ms at the start (phone being moved?). Lines too unsteady for a clean speed verdict; the bond kept going where direct stalled. Bond left off; repeat after the phone is placed.

**14.11.2026 08:05:** the Nothing moved to a tree (better signal) left USB: v68 bond stepped aside by itself ("only one line"), cable alone 32 Mbit/s steady. Marko chose its hotspot: switched on over adb via Tailscale (100.67.149.40:5555, quick-settings tile; SSID "Something", 2.4 GHz ch 13), but the Mac does not see it from the tree (out of range); the Mac back on mantra.

**14.11.2026 08:20:** cable + hotspot "Something" (Nothing on the tree, 4G probe 70 Mbit/s) both in the pool at 08:06, but the bond made no leg on en0 (no log line: bug sent to the worker) and the Wi-Fi hop from the tree flapped (rtt ~300 ms; v62 health timeout 1.2 s too strict: adaptive timeout sent to the worker). Tool: MACRO_SKILLS tools/nothing_hotspot.py on|off|state (catalogue id nothing-hotspot-line).

**14.11.2026 08:21 v70 live:** the log now says why: "Something (en0) left the lines: NO DATA: the stripe's HTTPS probe through it failed twice"; bond.bypass names it. The hotspot from the tree fails HTTPS probes (one took 14 s): line quality, not the software. Bond correctly stays aside with one good line; direct runs 2.5 s / 3.9 s / stalled at 60 s, bond-aside runs 2.75-3.26 s. Next: the phone where both its 4G and the Wi-Fi hop to the Mac are good (or a long USB cable), then the clean bonded test.

**14.11.2026 08:27 Brave test (Marko: Svemir's video "Happy Friday 13th - Super Grouper", youtu.be/TrKbGmc0acs):** plays in Brave, sound on, a clear picture, Brave Shields 12 blocked. Through the aggregate (bond aside, one good line): the stream used 0.1-1.7 Mbit/s in bursts, mostly over the hotspot "Something" (48 connections) beside AX88179B (23-36). A macOS box "control Brave Browser" (Apple Events) came up from my osascript: left for Marko.

**14.11.2026 08:35 the same video in Brave on chromium-vm (Marko: "test this video Friday 13 in the virtual machine"):** YouTube answers the Oracle address with "Sign in to confirm you're not a bot": the player never starts (readyState 0, 13.8 MB of page and scripts in 45 s, 0.6-2.8 Mbit/s). Consequence for bonding: every bonded connection leaves from 130.61.181.83, so YouTube (and other bot-checking sites) will show this check to the Mac while bond is on; a signed-in YouTube session, or a direct-path exception for such sites, is needed.

**14.11.2026 08:45:** after Marko signed in to YouTube in the VM's Brave (profile vm-brave), Svemir's video plays there (sound icon, picture, signed-in avatar; 9 MB in 25 s ≈ 2 Mbit/s; the VM's CPU shows 100 %). The Nothing moved near the desk: the Mac hears its hotspot at -63 dBm, pages via it 0.27-0.46 s, both lines in the pool (Something 71 Mbit/s).

**14.11.2026 08:50 CLEAN BONDED TEST (v70, cable AX88179B rtt 40 ms + Nothing hotspot "Something" near the desk rtt 39 ms):** 10 MB one stream: direct 4.58 / 5.91 / 2.76 s (18 / 14 / 30 Mbit/s); bonded 2.32 / 2.26 / 1.64 s (36 / 37 / 51 Mbit/s): about twice as fast, both legs used (Something 19.4 MB, AX88179B 12.2 MB; relay estimates 32.6 / 20.5 Mbit/s); pages through the bond 0.21-0.31 s. Bond left off pending Marko (sites see 130.61.181.83: YouTube bot check without sign-in).

**14.11.2026 07:54 UTC VM cleanup (Marko: "stop all unnecessary process on vm like brave etc for full power", "keep frankfurt servers", "yes"):** stopped (not disabled) Brave, Firefox WhatsApp Web + wa-door.service (its 60 s watchdog), chromium-vm-claude-app.service, the Android container pixel7b + pixel7d.service + pixel7-jobs.service. Kept: ckbond, tailscaled, ssh, chromium-vm-xvnc, Chrome (chromium-vm-session restarts it), Queen, Claude Code (tmux). Memory used 7.6 GB → 3.4 GB, load 3.3 → 0.4. Restart: systemctl --user start wa-door; sudo systemctl start pixel7d pixel7-jobs chromium-vm-claude-app. MAC_SES6 told.

**14.11.2026 08:45 (Marko: "bond should stay all the time"):** bond.json on permanently; both legs (AX88179B + Something), bypass none; the Mac's public address is 130.61.181.83; pages 0.32-0.48 s. With fewer than two good lines it steps aside by itself (v67+).

**14.11.2026 (Marko: "my whole machine now running on frankfurt ip that is fine buil that test ti t close the project"):** ck-bondcheck built and PASS; project closed.

## 14.11.2026, request 85 (UDP bonding and the rest, to a professional level)

> please continue developing this UDP and the rest of our aggregate connection keeper so it works on a professional level

**Status:** in progress (Opus worker): UDP through the bond (QUIC, calls, DNS), a direct list (YouTube and others skip Frankfurt), a privacy kill switch, DNS without leaks, the stripe showing the bond, ck-bondcheck extended.

## 14.11.2026, request 86 (a normal app: Dock, minimize, move, settings in the menu bar)

> also, please build Connection Keeper as a normal app, so I can start it from the dock. I can minimize it. I can move it. It has its settings in the menu bar, etc

**Status:** queued with the bonding worker, after the hitless transitions (request 85).
