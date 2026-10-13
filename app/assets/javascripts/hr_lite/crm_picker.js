// Type-ahead for [data-hrl-crm="<search url>"]: typing fills the <select
// name="crm_ref"> with matching leads. Without JS the select just stays empty.
(function () {
  "use strict";
  function setup(box) {
    var input = box.querySelector("input[type=search]");
    var select = box.querySelector("select");
    var timer;
    input.addEventListener("input", function () {
      clearTimeout(timer);
      var q = input.value.trim();
      if (q.length < 2) return;
      timer = setTimeout(function () {
        fetch(box.dataset.hrlCrm + "?q=" + encodeURIComponent(q), { headers: { Accept: "application/json" }, credentials: "same-origin" })
          .then(function (r) { return r.ok ? r.json() : []; })
          .then(function (leads) {
            select.length = 1;
            leads.forEach(function (lead) { select.add(new Option(lead.label, lead.id)); });
            if (leads.length) select.selectedIndex = 1;
          });
      }, 250);
    });
  }
  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-hrl-crm]").forEach(setup);
  });
})();
