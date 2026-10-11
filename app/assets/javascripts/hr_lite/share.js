// The ID card's Share button: draws both faces into one PNG and hands it to
// the phone's share sheet (WhatsApp, mail…). Desktops download it instead.
document.addEventListener("click", async function (event) {
  const button = event.target.closest("[data-hrl-share]");
  if (!button) return;

  button.disabled = true;
  try {
    // Front and back side by side in one picture, even where the page stacks them.
    const faces = document.querySelector(".hrl-idcard-faces");
    const card = faces.querySelector(".hrl-idcard").getBoundingClientRect();
    const pad = 24;
    const blob = await window.htmlToImage.toBlob(faces, {
      width: card.width * 2 + pad * 3,
      height: card.height + pad * 2,
      style: { flexWrap: "nowrap", gap: `${pad}px`, padding: `${pad}px`, margin: "0", justifyContent: "flex-start" },
      pixelRatio: 2,
      backgroundColor: "#ffffff",
      filter: (node) => !node.classList?.contains("hrl-idcard__label")
    });
    const file = new File([blob], button.dataset.hrlShare, { type: "image/png" });
    if (navigator.canShare?.({ files: [file] })) {
      await navigator.share({ files: [file], title: "ID card" });
    } else {
      const link = Object.assign(document.createElement("a"), { href: URL.createObjectURL(file), download: file.name });
      link.click();
      setTimeout(() => URL.revokeObjectURL(link.href), 1000);
    }
  } catch (error) {
    if (error.name !== "AbortError") alert("Could not make the image. Use Print instead.");
  } finally {
    button.disabled = false;
  }
});
