// Quick picks for the status form: a tap puts that status in the text box.
(function () {
  "use strict";
  document.addEventListener("click", function (e) {
    var b = e.target.closest && e.target.closest("[data-hrl-pick]");
    if (!b) return;
    var input = b.closest("form").querySelector("input[name=text]");
    input.value = b.dataset.hrlPick;
    input.focus();
  });
})();
