// "Select all" for a list of checkboxes in one form.
// Markup contract: <input type="checkbox" data-hrl-select-all="candidate_ids[]">.
// Ticking it ticks every box of that name in the same form; unticking any row
// unticks it again. The server still reads the box itself, so it works without JS.
(function () {
  "use strict";

  document.addEventListener("change", function (event) {
    var box = event.target;
    var form = box.form;
    if (!form) return;
    var all = form.querySelector("[data-hrl-select-all]");
    if (!all) return;
    var rows = form.querySelectorAll('input[name="' + all.getAttribute("data-hrl-select-all") + '"]');
    if (box === all) {
      rows.forEach(function (row) { row.checked = all.checked; });
    } else if (box.name === all.getAttribute("data-hrl-select-all") && !box.checked) {
      all.checked = false;
    }
  });
})();
