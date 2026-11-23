// The words of speedtest.net as a person reads them, the same as Tools/speedtest-firefox reads them (DECLINE_JS, GO_JS,
// RESULT_JS there): the hidden TEST of each row (Sources/App/LineTest.swift) evaluates these three expressions.
// Each one starts after its line "//== NAME". v89 (request 99).
//== DECLINE
(function () {
  const vis = e => !!(e && e.offsetParent);
  const words = ["reject all", "reject", "decline", "only necessary", "necessary only", "continue without accepting"];
  const b = [...document.querySelectorAll("button, a")].find(e => vis(e) && words.includes(e.innerText.trim().toLowerCase()));
  if (b) { b.click(); return "declined"; }
  return "";
})()
//== GO
(function () {
  const vis = e => !!(e && e.offsetParent);
  const go = [...document.querySelectorAll("button, a")].find(e => vis(e) && e.innerText && e.innerText.trim() === "GO")
          || document.querySelector('.js-start-test, a[aria-label^="start speed test"]');
  if (go && vis(go)) { go.click(); return "go"; }
  return "";
})()
//== RESULT
(function () {
  const lines = (document.querySelector("main") || document.body).innerText.split("\n").map(t => t.trim()).filter(t => t);
  const after = (label) => { const i = lines.findIndex(t => t.toUpperCase() === label); const v = i >= 0 ? lines[i + 1] : "";
                             return /^[0-9.]+$/.test(v) ? v : ""; };
  const ip = lines.find(t => /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/.test(t)) || "";
  const ipAt = lines.indexOf(ip);
  return {down: after("DOWNLOAD MBPS"), up: after("UPLOAD MBPS"), ping: after("PING MS"), unit: "Mbps",
          ip: ip, isp: ipAt > 0 ? lines[ipAt - 1] : "", url: location.href, done: /\/result\//.test(location.href)};
})()
//== TEXT
(function () {
  return location.href + " | " + (document.querySelector("main") || document.body).innerText.split("\n").map(t => t.trim()).filter(t => t).slice(0, 40).join(" / ");
})()
//== GOVISIBLE
(function () {
  const vis = e => !!(e && e.offsetParent);
  const go = [...document.querySelectorAll("button, a")].find(e => vis(e) && e.innerText && e.innerText.trim() === "GO")
          || document.querySelector('.js-start-test, a[aria-label^="start speed test"]');
  return !!(go && vis(go));
})()
