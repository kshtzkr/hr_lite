// Confirmation prompts for destructive actions.
//
// The views carry `data-turbo-confirm` on the forms that delete a draft
// payroll run, remove a kudos, offboard someone or withdraw a resignation —
// but the engine deliberately ships no Turbo and no Stimulus, so nothing was
// ever reading that attribute. Every one of those buttons fired on the first
// click with no prompt at all.
//
// Same attribute name so the markup does not change, and a no-op when a host
// app does load Turbo (Turbo handles it first; two prompts would be worse
// than none).
(function () {
  if (window.Turbo) return;

  document.addEventListener(
    "submit",
    function (event) {
      var form = event.target;
      if (!form || form.nodeName !== "FORM") return;

      var message = form.getAttribute("data-turbo-confirm");
      if (message && !window.confirm(message)) {
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      // Double-submit guard (data-disable-with is inert without Turbo/ujs). The
      // timeout lets the submitter's value post first; geo punch runs its own.
      if (!form.hasAttribute("data-hrl-geo-punch") && event.submitter) {
        var b = event.submitter;
        setTimeout(function () { b.disabled = true; b.setAttribute("aria-busy", "true"); }, 0);
      }
    },
    true // capture, so the check runs before any other submit handler
  );

  // Back restores a submitted page from the bfcache with its button still locked.
  window.addEventListener("pageshow", function (event) {
    if (!event.persisted) return;
    document.querySelectorAll("form:not([data-hrl-geo-punch]) [aria-busy]").forEach(function (b) {
      b.disabled = false;
      b.removeAttribute("aria-busy");
    });
  });
})();
