for (const card of document.querySelectorAll(".preview")) {
  const previews = [...card.querySelectorAll("object")];
  const button = card.querySelector("button");
  const action = button.dataset.action;
  const label = card.querySelector("h2, h3").textContent;
  const motionPreference = window.matchMedia("(prefers-reduced-motion: reduce)");

  function animations() {
    return previews.flatMap((preview) => preview.contentDocument?.getAnimations() ?? []);
  }

  function updateAvailability() {
    button.disabled = animations().length === 0;
  }

  for (const preview of previews) preview.addEventListener("load", updateAvailability);
  motionPreference.addEventListener("change", () => requestAnimationFrame(updateAvailability));
  updateAvailability();

  button.addEventListener("click", () => {
    const items = animations();
    if (action === "replay") {
      for (const animation of items) {
        animation.currentTime = 0;
        animation.play();
      }
      return;
    }
    const pause = items.some((animation) => animation.playState === "running");
    for (const animation of items) {
      if (pause) animation.pause();
      else animation.play();
    }
    button.textContent = pause ? "Devam et" : "Duraklat";
    button.setAttribute("aria-label", pause ? `${label} animasyonuna devam et` : `${label} animasyonunu duraklat`);
  });
}
