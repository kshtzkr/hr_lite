// The ID card's Print button. The engine ships no framework, and an inline
// onclick would need a CSP nonce the host may not issue.
document.addEventListener("click", function (event) {
  if (event.target.closest("[data-hrl-print]")) window.print();
});
