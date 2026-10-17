// Ticks "Xh YYm left" on [data-hrl-countdown="<iso time>"] (data-hrl-done when
// it runs out) and "Xh YYm so far" on [data-hrl-since]. Display only:
// the server ends the mode itself, with or without this page open.
(function () {
  "use strict";
  function hm(min) { return Math.floor(min / 60) + "h " + String(min % 60).padStart(2, "0") + "m"; }
  function tick() {
    document.querySelectorAll("[data-hrl-countdown]").forEach(function (el) {
      var left = Math.max(0, Math.round((Date.parse(el.dataset.hrlCountdown) - Date.now()) / 60000));
      el.textContent = left === 0 ? (el.dataset.hrlDone || "ended") : hm(left) + " left";
    });
    document.querySelectorAll("[data-hrl-since]").forEach(function (el) {
      el.textContent = hm(Math.max(0, Math.floor((Date.now() - Date.parse(el.dataset.hrlSince)) / 60000))) + " so far";
    });
  }
  document.addEventListener("DOMContentLoaded", function () { tick(); setInterval(tick, 30000); });
  // A PWA brought back from the background repaints at once, not on the next tick.
  document.addEventListener("visibilitychange", function () { if (!document.hidden) tick(); });
})();
