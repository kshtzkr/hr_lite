// Phones have no hover, so an SVG chart's <title> never shows there. Tapping
// (or tabbing to) a [data-hrl-tip] segment shows its title in a small box.
(function () {
  "use strict";
  var tip;
  function hide() { if (tip) tip.hidden = true; }
  function show(el) {
    var title = el.querySelector("title");
    if (!title) return;
    if (!tip) {
      tip = document.createElement("div");
      tip.className = "hrl-chart-tip";
      tip.setAttribute("role", "status");
      document.body.appendChild(tip);
    }
    tip.textContent = title.textContent;
    tip.hidden = false;
    var box = el.getBoundingClientRect();
    var left = Math.min(Math.max(8, box.left + window.scrollX), window.scrollX + document.documentElement.clientWidth - tip.offsetWidth - 8);
    tip.style.left = left + "px";
    tip.style.top = (box.top + window.scrollY - tip.offsetHeight - 6) + "px";
  }
  document.addEventListener("click", function (e) {
    var el = e.target.closest && e.target.closest("[data-hrl-tip]");
    el ? show(el) : hide();
  });
  document.addEventListener("focusin", function (e) {
    if (e.target.closest && e.target.closest("[data-hrl-tip]")) show(e.target.closest("[data-hrl-tip]"));
  });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") hide(); });
})();
