// Emoji grid for the status form: a tap puts that emoji in the input.
(function () {
  "use strict";
  document.addEventListener("click", function (e) {
    var b = e.target.closest && e.target.closest("[data-hrl-emoji]");
    if (!b) return;
    var input = b.closest("form").querySelector("input[name=emoji]");
    input.value = b.dataset.hrlEmoji;
    input.focus();
  });
})();
