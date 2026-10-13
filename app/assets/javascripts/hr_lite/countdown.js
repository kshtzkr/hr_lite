// Ticks "Xh YYm left" on [data-hrl-countdown="<iso time>"]. Display only:
// the server ends the mode itself, with or without this page open.
(function () {
  "use strict";
  function tick() {
    document.querySelectorAll("[data-hrl-countdown]").forEach(function (el) {
      var left = Math.max(0, Math.round((Date.parse(el.dataset.hrlCountdown) - Date.now()) / 60000));
      el.textContent = left === 0 ? "ended" : Math.floor(left / 60) + "h " + String(left % 60).padStart(2, "0") + "m left";
    });
  }
  document.addEventListener("DOMContentLoaded", function () { tick(); setInterval(tick, 30000); });
})();
