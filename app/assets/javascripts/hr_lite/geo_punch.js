// Dependency-free geolocation capture for punch forms.
// Markup contract:
//   <form data-hrl-geo-punch [data-hrl-geo-required]>
//     <input type="hidden" name="lat"><input type="hidden" name="lng">
//     <input type="hidden" name="accuracy_m"><input type="hidden" name="geo_status">
//     <button type="submit">…</button>
//     <p data-hrl-geo-status role="status" aria-live="polite"></p>  (not hidden, or the first message is missed)
//   </form>
// A denied permission holds the punch; timeout/unavailable submit anyway
// with geo_status set (the server flags them) — unless the form is marked
// data-hrl-geo-required, which holds those too. A held punch shows how to
// turn location on for this device: no web page can open device settings.
(function () {
  "use strict";

  // Steps per device, matched on the user agent. iPadOS reports a Mac UA, so a
  // touch-capable "Mac" counts as iOS.
  function locationSteps() {
    var ua = navigator.userAgent;
    var ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
    if (ios) {
      var app = /CriOS/.test(ua) ? "Chrome" : /FxiOS/.test(ua) ? "Firefox" : /EdgiOS/.test(ua) ? "Edge" : null;
      return [
        "Open Settings → Privacy & Security → Location Services and turn it on.",
        app ? "In Settings, open Apps → " + app + " → Location and choose While Using the App."
            : "In Settings, open Apps → Safari → Location and choose Allow (or Ask).",
        "Come back here, reload the page and tap again."
      ];
    }
    if (/Android/.test(ua)) {
      var samsung = /SamsungBrowser/.test(ua);
      return [
        "Swipe down from the top of the screen and turn Location on.",
        samsung ? "In Samsung Internet, tap ☰ → Settings → Sites and downloads → Site permissions → Location, and allow this site."
                : "Tap the icon left of the web address → Permissions → Location → Allow. (Or ⋮ → Settings → Site settings → Location.)",
        "Reload the page and tap again."
      ];
    }
    var steps = [];
    if (/Firefox/.test(ua)) steps.push("Click the icon left of the web address and remove the blocked Location permission.");
    else if (/Safari/.test(ua) && !/Chrome|Chromium|Edg/.test(ua)) steps.push("Open Safari → Settings → Websites → Location and set this site to Allow.");
    else steps.push("Click the icon left of the web address → Location → Allow.");
    if (/Mac OS X|Macintosh/.test(ua)) steps.push("On the Mac, open System Settings → Privacy & Security → Location Services and turn it on for this browser.");
    else if (/Windows/.test(ua)) steps.push("In Windows, open Settings → Privacy & security → Location and turn on location access.");
    steps.push("Reload the page and tap again.");
    return steps;
  }

  function showHelp(label, headline) {
    if (!label) return;
    label.textContent = headline;
    var list = document.createElement("ol");
    list.className = "hrl-geo-help";
    locationSteps().forEach(function (step) {
      var item = document.createElement("li");
      item.textContent = step;
      list.appendChild(item);
    });
    label.appendChild(list);
  }

  function setup(form) {
    var fields = {
      lat: form.querySelector("[name=lat]"),
      lng: form.querySelector("[name=lng]"),
      accuracy: form.querySelector("[name=accuracy_m]"),
      status: form.querySelector("[name=geo_status]")
    };
    var button = form.querySelector("[type=submit]");
    var label = form.querySelector("[data-hrl-geo-status]");
    var required = form.hasAttribute("data-hrl-geo-required");
    var locating = false;

    function send(status) {
      fields.status.value = status;
      locating = false;
      form.submit();
    }

    function hold(headline) {
      locating = false;
      if (button) { button.disabled = false; button.removeAttribute("aria-busy"); }
      showHelp(label, headline);
    }

    form.addEventListener("submit", function (event) {
      if (locating || fields.status.value) return; // second pass: let it through
      event.preventDefault();
      locating = true;
      if (button) { button.disabled = true; button.setAttribute("aria-busy", "true"); }
      if (label) { label.hidden = false; label.textContent = "Getting location…"; }

      if (!navigator.geolocation) {
        if (required) hold("This browser cannot share your location. Open this page in Chrome or Safari.");
        else send("unavailable");
        return;
      }

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
          if (err && err.code === 1) { hold("Location is blocked. To allow it:"); return; }
          if (required) { hold("Couldn't get your location. Check that location is on:"); return; }
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
