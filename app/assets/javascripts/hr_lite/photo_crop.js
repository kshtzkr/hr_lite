// ID card photo: the chosen picture previews inside the card's own frame.
// Drag to move it, slide to zoom, and the upload is exactly what the frame shows.
(function () {
  const input = document.querySelector("[data-hrl-photo-input]");
  if (!input) return;
  const frame = document.querySelector(".hrl-idcard__photo");
  const zoom = document.querySelector("[data-hrl-photo-zoom]");
  let img = null, base = 1, scale = 1, x = 0, y = 0, cropped = false;

  const size = () => [ img.naturalWidth * base * scale, img.naturalHeight * base * scale ];
  function place() {
    const [ w, h ] = size();
    x = Math.min(0, Math.max(frame.clientWidth - w, x));
    y = Math.min(0, Math.max(frame.clientHeight - h, y));
    img.style.cssText = `position:absolute;left:0;top:0;max-width:none;width:${w}px;height:${h}px;transform:translate(${x}px,${y}px);cursor:grab`;
  }

  input.addEventListener("change", function () {
    const file = input.files[0];
    if (!file) return;
    img = new Image();
    img.onload = function () {
      base = Math.max(frame.clientWidth / img.naturalWidth, frame.clientHeight / img.naturalHeight);
      scale = 1;
      zoom.value = 1;
      x = (frame.clientWidth - img.naturalWidth * base) / 2;
      y = (frame.clientHeight - img.naturalHeight * base) / 2;
      frame.replaceChildren(img);
      frame.style.touchAction = "none";
      zoom.closest("[data-hrl-photo-adjust]").hidden = false;
      place();
    };
    img.src = URL.createObjectURL(file);
  });

  zoom.addEventListener("input", function () {
    const ratio = zoom.value / scale, cx = frame.clientWidth / 2, cy = frame.clientHeight / 2;
    x = cx - (cx - x) * ratio;
    y = cy - (cy - y) * ratio;
    scale = Number(zoom.value);
    place();
  });

  frame.addEventListener("pointerdown", function (down) {
    if (!img) return;
    frame.setPointerCapture(down.pointerId);
    let lastX = down.clientX, lastY = down.clientY;
    const move = function (event) {
      x += event.clientX - lastX; y += event.clientY - lastY;
      lastX = event.clientX; lastY = event.clientY;
      place();
    };
    frame.addEventListener("pointermove", move);
    frame.addEventListener("pointerup", () => frame.removeEventListener("pointermove", move), { once: true });
  });

  input.form.addEventListener("submit", function (event) {
    if (!img || cropped) return;
    event.preventDefault();
    const k = base * scale, canvas = document.createElement("canvas");
    canvas.width = 560; canvas.height = Math.round(560 * frame.clientHeight / frame.clientWidth);
    canvas.getContext("2d").drawImage(img, -x / k, -y / k, frame.clientWidth / k, frame.clientHeight / k, 0, 0, canvas.width, canvas.height);
    canvas.toBlob(function (blob) {
      const files = new DataTransfer();
      files.items.add(new File([ blob ], "photo.jpg", { type: "image/jpeg" }));
      input.files = files.files;
      cropped = true;
      input.form.requestSubmit();
    }, "image/jpeg", 0.9);
  });
})();
