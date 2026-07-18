// Dependency-free @mention autocomplete for textareas.
// Markup contract:
//   <div class="hrl-mention-wrap" data-hrl-mention data-search-url="...">
//     <textarea ...></textarea>
//   </div>
// Picking a user inserts the visible marker "@[Name](id) " which the server
// parses via HrLite::MentionParser.
(function () {
  "use strict";

  var TRIGGER = /@([\w.\-]{1,30})$/;

  function debounce(fn, ms) {
    var t;
    return function () {
      var args = arguments, self = this;
      clearTimeout(t);
      t = setTimeout(function () { fn.apply(self, args); }, ms);
    };
  }

  function setup(wrap) {
    var textarea = wrap.querySelector("textarea");
    var url = wrap.getAttribute("data-search-url");
    if (!textarea || !url) return;

    var menu = document.createElement("div");
    menu.className = "hrl-mention-menu";
    menu.hidden = true;
    wrap.appendChild(menu);
    var active = -1;

    function close() { menu.hidden = true; menu.innerHTML = ""; active = -1; }

    function pick(item) {
      var caret = textarea.selectionStart;
      var before = textarea.value.slice(0, caret);
      var after = textarea.value.slice(caret);
      var replaced = before.replace(TRIGGER, "@[" + item.text + "](" + item.value + ") ");
      textarea.value = replaced + after;
      var pos = replaced.length;
      textarea.focus();
      textarea.setSelectionRange(pos, pos);
      close();
    }

    function renderResults(items) {
      close();
      if (!items.length) return;
      items.slice(0, 8).forEach(function (item) {
        var btn = document.createElement("button");
        btn.type = "button";
        btn.textContent = item.text;
        btn.addEventListener("mousedown", function (e) { e.preventDefault(); pick(item); });
        menu.appendChild(btn);
      });
      menu.hidden = false;
    }

    var lookup = debounce(function (query) {
      fetch(url + "?q=" + encodeURIComponent(query), { headers: { Accept: "application/json" } })
        .then(function (r) { return r.ok ? r.json() : []; })
        .then(renderResults)
        .catch(close);
    }, 200);

    textarea.addEventListener("input", function () {
      var before = textarea.value.slice(0, textarea.selectionStart);
      var match = TRIGGER.exec(before);
      if (match && match[1].length >= 2) lookup(match[1]);
      else close();
    });

    textarea.addEventListener("keydown", function (e) {
      if (menu.hidden) return;
      var buttons = menu.querySelectorAll("button");
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        e.preventDefault();
        active = e.key === "ArrowDown" ? Math.min(active + 1, buttons.length - 1) : Math.max(active - 1, 0);
        buttons.forEach(function (b, i) { b.classList.toggle("hrl-active", i === active); });
      } else if (e.key === "Enter" && active >= 0) {
        e.preventDefault();
        buttons[active].dispatchEvent(new MouseEvent("mousedown"));
      } else if (e.key === "Escape") {
        close();
      }
    });

    document.addEventListener("click", function (e) {
      if (!wrap.contains(e.target)) close();
    });
  }

  function init() {
    document.querySelectorAll("[data-hrl-mention]").forEach(setup);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
