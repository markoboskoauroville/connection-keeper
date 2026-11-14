// Only the test frame of speedtest.net (v58, request 77, Marko 14.11.2026: "I need only Go, Download, Upload speeds,
// this pink line, Telemach, this part only ... remove Sign In and all the other nonsense"). The 2026 page has no stable
// class names, so the page is cut by its structure: the column .pure-u-custom-speedtest, and inside it the frame.
// window.ckFull = true shows the whole page again (the eye on the browser's bottom bar).
(function () {
  const HIDE = "ck-hide";
  const css = document.createElement("style");
  css.textContent = `
    html:not(.ck-full) .${HIDE} { display: none !important; }
    html:not(.ck-full) .pure-g { padding-top: 0 !important; margin-top: 0 !important; justify-content: center !important; }
    html:not(.ck-full) .pure-u-custom-speedtest { margin: 0 auto !important; padding-top: 24px !important; }
    html:not(.ck-full), html:not(.ck-full) body { overflow-x: hidden !important; }`;
  const hide = (e) => { if (e && !e.classList.contains(HIDE)) e.classList.add(HIDE); };
  const text = (e) => (e.innerText || "").replace(/\s+/g, " ").trim();

  function tidy() {
    document.documentElement.classList.toggle("ck-full", !!window.ckFull);
    if (!css.isConnected && document.head) document.head.appendChild(css);
    const col = document.querySelector(".pure-u-custom-speedtest");
    if (!col) return;
    // every branch from the column up to <body> keeps only the way to the column
    for (let e = col; e && e.parentElement && e !== document.body; e = e.parentElement) {
      for (const s of e.parentElement.children) {
        if (s === e || s.tagName === "SCRIPT" || s.tagName === "STYLE" || s.tagName === "LINK") continue;
        if (s.id === "onetrust-consent-sdk") continue;          // the privacy box must stay answerable
        hide(s);
      }
    }
    // in the column: the frame and its overlays stay; the cards and boxes from #content-card-stack down go
    let after = false;
    for (const c of col.children) {
      if (c.id === "content-card-stack") after = true;
      if (after) hide(c);
    }
    // in the frame: the RESULTS · SETTINGS tabs and the Connections Multi · Single row go
    const frame = col.querySelector(":scope > .isolate") || col;
    for (const e of frame.querySelectorAll("div")) {
      const t = text(e);
      if (/^RESULTS SETTINGS$/i.test(t) || /^Connections( Multi)?( Single)?$/i.test(t)) hide(e);
    }
  }
  window.ckTidy = tidy;
  let queued = false;
  new MutationObserver(() => { if (!queued) { queued = true; requestAnimationFrame(() => { queued = false; tidy(); }); } })
    .observe(document.documentElement, { childList: true, subtree: true });
  tidy();
})();
