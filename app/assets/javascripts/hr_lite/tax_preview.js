// Live tax: a form with data-hrl-tax-preview="<url>" posts what is on screen
// (files left out) as it is typed, and the server's worked-out tax replaces
// #hrl-tax-preview. Nothing is saved; the Save button still does that.
(function () {
  "use strict";
  var form = document.querySelector("form[data-hrl-tax-preview]");
  var panel = document.getElementById("hrl-tax-preview");
  if (!form || !panel) return;

  var timer;
  function refresh() {
    var data = new FormData(form);
    Array.from(data.keys()).forEach(function (key) { if (/\[proofs\]/.test(key)) data.delete(key); });
    data.delete("_method");
    fetch(form.dataset.hrlTaxPreview, { method: "POST", body: data, credentials: "same-origin", headers: { "Accept": "text/html" } })
      .then(function (response) { return response.ok ? response.text() : null; })
      .then(function (html) { if (html) panel.innerHTML = html; });
  }
  var rupees = new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 });
  // The limit bar and "₹X of the ₹Y limit counts" follow the amount as typed.
  function updateCap(input) {
    var field = input.closest(".hrl-field");
    var hint = field && field.querySelector("[data-hrl-cap]");
    if (!hint) return;
    var cap = Number(hint.dataset.hrlCap);
    var counts = Math.min(Math.max(Number(input.value.replace(/[^0-9.]/g, "")) || 0, 0), cap);
    field.querySelector("progress").value = counts;
    hint.textContent = rupees.format(counts) + " of the " + rupees.format(cap) + " limit counts";
  }
  function schedule(event) {
    if (event.target.type === "file") return;
    if (/declared_amount/.test(event.target.name)) updateCap(event.target);
    clearTimeout(timer);
    timer = setTimeout(refresh, 400);
  }
  form.addEventListener("input", schedule);
  form.addEventListener("change", schedule);
})();
