// Keeps the current screen in view. The rail and the phone's More sheet both
// scroll, and a Manage item sits below the fold. scrollIntoView is avoided on
// purpose: it would scroll the page as well as the menu.
(function () {
  function centre(panel) {
    var link = panel && panel.querySelector(".hrl-nav__link--active");
    if (!link) return;
    var box = panel.getBoundingClientRect();
    var item = link.getBoundingClientRect();
    panel.scrollTop += item.top - box.top - (box.height - item.height) / 2;
  }

  centre(document.querySelector(".hrl-side"));

  var more = document.querySelector(".hrl-tabbar__more");
  if (more) {
    more.addEventListener("toggle", function () {
      if (more.open) centre(more.querySelector(".hrl-sheet"));
    });
  }
})();
