// Dependency-free type-to-filter for long selects.
// Markup contract: <select data-hrl-filter="Type a name to filter">. A search
// box with that label goes in front of the select, and typing keeps only the
// options whose text matches. The select keeps its name and submits as before;
// without JS it stays a plain select. Options are removed, not hidden, because
// iOS Safari's picker ignores hidden options.
(function () {
  "use strict";

  function setup(select) {
    var all = Array.prototype.slice.call(select.options);
    var picked = select.value; // the stored pick, or the admin's own choice from the list
    var input = document.createElement("input");
    input.type = "search";
    input.className = "hrl-input hrl-filter";
    input.autocomplete = "off";
    input.placeholder = select.getAttribute("data-hrl-filter") || "Type to filter";
    input.setAttribute("aria-label", input.placeholder);
    select.parentNode.insertBefore(input, select);

    function filter() {
      var q = input.value.trim().toLowerCase();
      var value = q ? select.value : picked; // an empty box puts the stored pick back
      var keep = all.filter(function (o) { return o.text.toLowerCase().indexOf(q) !== -1; });
      if (!keep.length) return; // no match: leave the list as is, so the field still submits
      select.replaceChildren.apply(select, keep);
      // Keep the current pick while it still matches, else take the first match.
      if (keep.some(function (o) { return o.value === value; })) select.value = value;
      else select.selectedIndex = 0;
    }

    select.addEventListener("change", function () { picked = select.value; });
    input.addEventListener("input", filter);
    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter") e.preventDefault(); // never submit the form half-filled
      if (e.key === "Escape" && input.value) { e.preventDefault(); input.value = ""; filter(); }
    });
  }

  function init() {
    document.querySelectorAll("select[data-hrl-filter]").forEach(setup);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
