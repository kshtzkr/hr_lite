// The search palette: ⌘K / Ctrl+K or any [data-hrl-search-open] link opens it.
// Typing loads the short results from /search?frame=1 after a pause; Enter
// opens the full page; arrows move through results; Escape closes (native).
// Without JS (or <dialog>) the links simply open the search page.
(function () {
  var dialog = document.querySelector("[data-hrl-search]");
  if (!dialog || !dialog.showModal) return;
  var form = dialog.querySelector("form[role=search]");
  var input = form.querySelector("input");
  var out = dialog.querySelector("[data-hrl-search-results]");
  var timer;

  function open(event) {
    if (event) event.preventDefault();
    var more = document.querySelector(".hrl-tabbar__more[open]");
    if (more) more.open = false; // opened from the phone's More sheet
    if (!dialog.open) dialog.showModal();
    input.focus();
    input.select();
  }

  document.addEventListener("keydown", function (event) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") open(event);
  });
  document.querySelectorAll("[data-hrl-search-open]").forEach(function (link) {
    link.addEventListener("click", open);
  });
  dialog.addEventListener("click", function (event) { if (event.target === dialog) dialog.close(); });

  input.addEventListener("input", function () {
    clearTimeout(timer);
    timer = setTimeout(function () {
      fetch(form.action + "?frame=1&q=" + encodeURIComponent(input.value), { credentials: "same-origin", cache: "no-store" })
        .then(function (response) { return response.ok ? response.text() : ""; })
        .then(function (html) { out.innerHTML = html; });
    }, 180);
  });

  dialog.addEventListener("keydown", function (event) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    var links = Array.prototype.slice.call(out.querySelectorAll("a"));
    if (!links.length) return;
    event.preventDefault();
    var at = links.indexOf(document.activeElement);
    at = event.key === "ArrowDown" ? Math.min(at + 1, links.length - 1) : at - 1;
    (at < 0 ? input : links[at]).focus();
  });
})();
