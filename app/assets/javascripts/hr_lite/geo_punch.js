// Dependency-free geolocation capture for punch forms.
// Markup contract:
//   <form data-hrl-geo-punch>
//     <input type="hidden" name="lat"><input type="hidden" name="lng">
//     <input type="hidden" name="accuracy_m"><input type="hidden" name="geo_status">
//     <button type="submit">…</button>
//     <p data-hrl-geo-status role="status" aria-live="polite"></p>  (not hidden, or the first message is missed)
//   </form>
// A denied permission holds the punch; timeout/unavailable submit anyway
// with geo_status set; the server flags them.
(function () {
  "use strict";

  function setup(form) {
    var fields = {
      lat: form.querySelector("[name=lat]"),
      lng: form.querySelector("[name=lng]"),
      accuracy: form.querySelector("[name=accuracy_m]"),
      status: form.querySelector("[name=geo_status]")
    };
    var button = form.querySelector("[type=submit]");
    var label = form.querySelector("[data-hrl-geo-status]");
    var locating = false;

    function send(status) {
      fields.status.value = status;
      locating = false;
      form.submit();
    }

    form.addEventListener("submit", function (event) {
      if (locating || fields.status.value) return; // second pass: let it through
      event.preventDefault();
      locating = true;
      if (button) { button.disabled = true; button.setAttribute("aria-busy", "true"); }
      if (label) { label.hidden = false; label.textContent = "Getting location…"; }

      if (!navigator.geolocation) { send("unavailable"); return; }

      navigator.geolocation.getCurrentPosition(
        function (pos) {
          fields.lat.value = pos.coords.latitude.toFixed(6);
          fields.lng.value = pos.coords.longitude.toFixed(6);
          fields.accuracy.value = Math.round(pos.coords.accuracy);
          send("ok");
        },
        function (err) {
          // Browsers ask only once; a past "Don't allow" denies silently forever.
          // Hold the punch so it is never filed (and flagged) without GPS.
          if (err && err.code === 1) {
            locating = false;
            if (button) { button.disabled = false; button.removeAttribute("aria-busy"); }
            if (label) label.textContent = "Location is blocked. Allow location for this site in your browser settings, then tap again.";
            return;
          }
          send("timeout");
        },
        { enableHighAccuracy: true, timeout: 10000, maximumAge: 60000 }
      );
    });
  }

  function init() {
    document.querySelectorAll("form[data-hrl-geo-punch]").forEach(setup);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
