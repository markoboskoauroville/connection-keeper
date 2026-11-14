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
    if (window.ckFull) { const root = document.getElementById("root"); if (root) root.style.removeProperty("transform"); ox = oy = 0; }
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
    // v59 (request 78): the result page's extras: Share, Result ID, the date row, the boxes under the frame
    for (const e of col.querySelectorAll("div, section")) {
      const t = text(e), h = e.getBoundingClientRect().height;
      if (h > 0 && h < 80 && /^(Share|Result ID)\b/i.test(t)) hide(e);
      if (/^(Desktop Apps|Feedback|How likely)/i.test(t) && !/^(Desktop Apps|Feedback|How likely)/i.test(text(e.parentElement))) hide(e);
    }
    if (!window.ckFull) measure(col);
  }

  // v59: the frame's box = every visible thing in the column put together; the page is scrolled so the box starts
  // at the window's 12 pt edge, and its size goes to the app, which makes the window exactly that big.
  const EDGE = 12;
  let last = "", ox = 0, oy = 0;
  function measure(col) {
    let l = 1e9, t = 1e9, r = -1e9, b = -1e9;
    const sx = window.scrollX - ox, sy = window.scrollY - oy;     // rects without our own shift
    for (const e of col.querySelectorAll("*")) {
      if (e.closest("." + HIDE)) continue;
      const leaf = e.children.length === 0 || /^(svg|img|canvas|button|video)$/i.test(e.tagName);
      if (!leaf || e.closest("svg") && e.tagName.toLowerCase() !== "svg") continue;
      const st = getComputedStyle(e);
      if (st.visibility === "hidden" || st.display === "none" || parseFloat(st.opacity) === 0) continue;
      if (e.children.length === 0 && !/^(svg|img|canvas|button|video|input)$/i.test(e.tagName) && !text(e)) continue;
      const q = e.getBoundingClientRect();
      if (q.width < 3 || q.height < 3) continue;
      l = Math.min(l, q.left + sx); t = Math.min(t, q.top + sy); r = Math.max(r, q.right + sx); b = Math.max(b, q.bottom + sy);
    }
    if (r <= l || b <= t) return;
    document.documentElement.style.setProperty("overflow", "hidden", "important");
    document.body.style.setProperty("overflow", "hidden", "important");
    window.scrollTo(0, 0);
    const root = document.getElementById("root") || document.body;
    ox = Math.round(EDGE - l); oy = Math.round(EDGE - t);
    root.style.setProperty("transform", `translate(${ox}px, ${oy}px)`, "important");
    const box = { w: Math.round(r - l), h: Math.round(b - t) };
    window.ckBox = box;
    const k = box.w + "x" + box.h;
    if (k !== last && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ckFrame) {
      last = k;
      window.webkit.messageHandlers.ckFrame.postMessage(box);
    }
  }
  window.ckTidy = tidy;
  window.addEventListener("resize", () => requestAnimationFrame(tidy));
  let queued = false;
  new MutationObserver(() => { if (!queued) { queued = true; requestAnimationFrame(() => { queued = false; tidy(); }); } })
    .observe(document.documentElement, { childList: true, subtree: true });
  tidy();
})();
