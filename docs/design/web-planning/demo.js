const sceneDefinitions = {
  kurulum: {
    video: "kurulum",
    title: "Kurulum", mac: "case-1-mac", phone: "case-1-iphone",
    alt: "Yedeğin kaydedileceği yeri seçme ekranı.",
    cue: "Ev Arşivi", detail: "Yazma izni var", meter: 100, node: "1880-251",
    beats: ["Yedekleme konumu kontrol ediliyor", "Boş alan ve yazma izni kontrol ediliyor"],
  },
  "canli-yedekleme": {
    video: "canli-yedekleme",
    title: "Yedekleme", mac: "case-3-mac", phone: "case-3-iphone",
    alt: "Yedekleme ilerlemesi, kalan süre ve kopyalanan dosya.",
    cue: "Yedekleme sürüyor", detail: "IMG_2841.HEIC · İndiriliyor", meter: 58, node: "1881-348",
    beats: ["IMG_2839.HEIC · Kontrol ediliyor", "IMG_2840.HEIC · Kopyalanıyor"],
  },
  koruma: {
    video: "koruma",
    title: "Yedek durumu", mac: "case-2-mac", phone: "case-2-iphone",
    alt: "Son yedekleme ve yedeklenen öğelerin özeti.",
    cue: "Yedeğin güncel", detail: "Bugün 09.18’de yedeklendi", node: "1880-404",
    beats: ["Son yedekleme kontrol ediliyor"],
  },
  baglanti: {
    video: "baglanti",
    title: "Bağlantı sorunu", mac: "case-4-mac", phone: "case-4-iphone",
    alt: "Yedekleme konumuna ulaşılamadığında bağlantıyı yeniden kurma adımları.",
    cue: "Ev Arşivi’ne ulaşılamadı", detail: "Son yedek dün 22.51’de alındı", node: "1881-497",
    beats: ["Ev Arşivi’nden yanıt bekleniyor"],
  },
  gecmis: {
    video: "gecmis",
    title: "Yedekleme geçmişi", mac: "history-mac",
    alt: "Önceki yedeklemeler ve kopyalanamayan dosyaların listesi.",
    cue: "3 dosya kopyalanamadı", detail: "Sonraki yedeklemede yeniden denenecek", node: "1904-860",
    beats: ["Son yedeklemenin ayrıntıları açılıyor", "Kopyalanamayan dosyalar gösteriliyor"],
  },
  "geri-yukleme": {
    title: "Geri yükleme", mac: "case-5-mac", phone: "case-5-iphone",
    alt: "Arşivden dosya seçme ve geri yükleme ekranı.",
    cue: "Ev sigortası.pdf", detail: "Kopyası seçtiğin klasöre kaydedilecek", node: "1882-461",
    beats: ["Dosya arşivde aranıyor", "Dosya ayrıntıları açılıyor"],
  },
  "menu-cubugu": {
    video: "menu-cubugu",
    title: "Menü çubuğu", mac: "menu-bar",
    alt: "Mac’in menü çubuğunda yedek durumunu gösteren menü.",
    cue: "Yedeğinin durumu", detail: "Mac’in menü çubuğu", node: "1912-787",
    beats: ["Güncel · Yedekleniyor · Bağlantı sorunu"],
  },
};

const root = document.documentElement;
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const narrow = matchMedia("(max-width: 52rem) and (min-height: 34.01rem)");
const heroReel = document.querySelector(".hero-reel");
const heroButtons = [...document.querySelectorAll("[data-hero-scene]")];
const steps = [...document.querySelectorAll("[data-chapter]")];
const chapterLinks = [...document.querySelectorAll(".chapter-nav a")];
const storyPanel = document.querySelector(".story-stage");
const storyLabel = document.querySelector("[data-story-label]");
const storyPlatform = document.querySelector(".story-stage-header > span");
const storyLink = document.querySelector("[data-story-link]");
const imageCache = new Map();

function stageFor(name) {
  const node = document.querySelector(`[data-stage="${name}"]`);
  return {
    node,
    devices: node.querySelector(".scene-devices"),
    mac: node.querySelector(".scene-mac"),
    video: node.querySelector(".scene-video"),
    phone: node.querySelector(".scene-phone"),
    caption: node.querySelector(".stage-cue"),
    title: node.querySelector(".cue-copy strong"),
    detail: node.querySelector(".cue-copy small"),
    signal: node.querySelector(".cue-signal"),
    number: node.querySelector(".cue-value"),
    meter: node.querySelector(".cue-meter"),
    fill: node.querySelector(".cue-meter > span"),
    static: node.hasAttribute("data-static"),
    effects: [],
    timers: [],
  };
}
const hero = stageFor("hero");
const story = stageFor("story");

function loadImage(name) {
  if (!name) return Promise.resolve(null);
  if (!imageCache.has(name)) {
    const image = new Image();
    image.src = `assets/${name}.webp?v=2`;
    const ready = image.decode().then(() => image).catch(() => {
      imageCache.delete(name);
      return null;
    });
    imageCache.set(name, ready);
  }
  return imageCache.get(name);
}

function playVideo(stage, restart = false) {
  const video = stage.video;
  if (!video || video.hidden) return;
  if (root.dataset.motion === "on" && stage.node.classList.contains("active-visual") && !document.hidden) {
    if (restart) video.currentTime = 0;
    video.play().catch(() => {});
  } else {
    video.pause();
  }
}

function showVideo(stage, scene) {
  const video = stage.video;
  if (!video) return;
  const name = stage.static ? null : scene.video;
  stage.mac.hidden = Boolean(name);
  video.hidden = !name;
  if (!name) {
    video.pause();
    return;
  }
  const src = `assets/recordings/${name}.mp4`;
  if (video.getAttribute("src") !== src) {
    video.poster = `assets/recordings/${name}-poster.jpg`;
    video.setAttribute("src", src);
  }
  video.setAttribute("aria-label", `Mac uygulamasından kayıt. ${scene.alt}`);
  playVideo(stage, true);
}

function stopStageEffects(stage) {
  for (const animation of stage.effects) animation.cancel();
  for (const timer of stage.timers) clearTimeout(timer);
  stage.effects.length = 0;
  stage.timers.length = 0;
  cancelAnimationFrame(stage.counterFrame);
}

function settleStage(stage) {
  stopStageEffects(stage);
  const key = stage.node.dataset.scene;
  const scene = sceneDefinitions[key];
  stage.detail.textContent = scene.detail;
  if (key === "canli-yedekleme") stage.number.textContent = `%${scene.meter}`;
  stage.video?.pause();
  stage.played = false;
}

function animateStage(stage, key, scene) {
  stage.played = true;
  playVideo(stage);
  const entry = {
    kurulum: { x: -20, y: 11, scale: .975 },
    "canli-yedekleme": { x: 14, y: 9, scale: .976 },
    koruma: { x: 0, y: 12, scale: .977 },
    baglanti: { x: -12, y: 8, scale: .979 },
    gecmis: { x: 15, y: 10, scale: .979 },
    "geri-yukleme": { x: 19, y: 0, scale: .979 },
    "menu-cubugu": { x: 0, y: -17, scale: .966 },
  }[key];
  const easing = "cubic-bezier(.16,.7,.26,1)";
  stage.effects = [
    stage.devices.animate(
      [{ opacity: .28, transform: `translate(${entry.x}px,${entry.y}px) scale(${entry.scale})` }, { opacity: 1, transform: "none" }],
      { duration: 620, easing },
    ),
    stage.caption.animate(
      [{ opacity: 0, transform: "translateY(10px) scale(.99)" }, { opacity: 1, transform: "none" }],
      { duration: 540, easing },
    ),
    stage.signal.animate(
      [{ transform: "scale(.78)" }, { transform: "scale(1.06)", offset: .68 }, { transform: "scale(1)" }],
      { duration: 490, easing },
    ),
  ];
  const beats = [...scene.beats, scene.detail];
  stage.detail.textContent = beats[0];
  for (const [index, line] of beats.slice(1).entries()) {
    stage.timers.push(setTimeout(() => { stage.detail.textContent = line; }, (index + 1) * 820));
  }
  if (scene.meter) stage.effects.push(stage.fill.animate(
    [{ transform: "scaleX(0.08)" }, { transform: "scaleX(1)" }], { duration: 1000, easing },
  ));
  if (key === "canli-yedekleme") {
    const start = performance.now();
    const tick = (now) => {
      const ratio = Math.min(1, (now - start) / 1050);
      stage.number.textContent = `%${Math.round(31 + (scene.meter - 31) * (1 - (1 - ratio) ** 3))}`;
      if (ratio < 1) stage.counterFrame = requestAnimationFrame(tick);
    };
    stage.counterFrame = requestAnimationFrame(tick);
  }
}

async function setScene(stage, key, animate = true) {
  const scene = sceneDefinitions[key];
  if (!scene || stage.request === key) return;
  stage.request = key;
  const [mac, phone] = await Promise.all([loadImage(scene.mac), loadImage(scene.phone)]);
  if (stage.request !== key) return;
  stopStageEffects(stage);
  if (mac) {
    stage.mac.src = mac.src;
    stage.mac.alt = `Mac ekran taslağı. ${scene.alt}`;
  }
  if (phone) {
    stage.phone.src = phone.src;
    stage.phone.alt = `iPhone ekran taslağı. ${scene.alt}`;
  }
  showVideo(stage, scene);
  stage.phone.hidden = !phone;
  stage.node.toggleAttribute("data-single-device", !phone);
  stage.node.dataset.scene = key;
  stage.ready = key;
  stage.played = false;
  stage.title.textContent = scene.cue;
  stage.detail.textContent = scene.detail;
  stage.number.textContent = key === "canli-yedekleme" ? `%${scene.meter}` : "";
  stage.meter.hidden = !scene.meter;
  stage.node.style.setProperty("--meter", `${scene.meter ?? 0}%`);
  if (animate && !stage.static && root.dataset.motion === "on" && stage.node.classList.contains("active-visual")) animateStage(stage, key, scene);
}

let heroVisible = false;
let heroTimer;
let heroIndex = 0;

function updateHeroTimer() {
  clearTimeout(heroTimer);
  if (heroFlowOn || hero.static) return;
  if (root.dataset.motion !== "on" || !heroVisible || document.hidden ||
      heroIndex >= heroButtons.length - 1 || heroReel.matches(":hover, :focus-within")) return;
  heroTimer = setTimeout(() => selectHero(heroIndex + 1), 1950);
}

function selectHero(index, animate = true) {
  if (heroFlowOn) { flowSelect(index, animate); return; }
  heroIndex = index;
  for (const [i, button] of heroButtons.entries()) button.setAttribute("aria-pressed", String(i === index));
  void setScene(hero, heroButtons[index].dataset.heroScene, animate);
  updateHeroTimer();
}

function setMotion() {
  const off = reduced.matches;
  root.dataset.motion = off ? "off" : "on";
  if (off) {
    for (const stage of [hero, story]) settleStage(stage);
  } else {
    for (const stage of [hero, story]) playVisible(stage);
  }
  updateHeroTimer();
  queueScrollUpdate();
}

reduced.addEventListener("change", setMotion);
for (const [i, button] of heroButtons.entries()) button.addEventListener("click", () => selectHero(i));
for (const type of ["pointerenter", "pointerleave", "focusin", "focusout"]) {
  heroReel.addEventListener(type, () => requestAnimationFrame(updateHeroTimer));
}
document.addEventListener("visibilitychange", () => {
  updateHeroTimer();
  for (const stage of [hero, story]) playVideo(stage);
});
document.querySelector("[data-restart-demo]").addEventListener("click", () => selectHero(0));

const stepSection = document.querySelector(".story-steps");
let currentChapter;

function selectChapter(key, animate = true) {
  if (currentChapter === key) return;
  currentChapter = key;
  const scene = sceneDefinitions[key];
  for (const step of steps) step.classList.toggle("current", step.id === key);
  for (const link of chapterLinks) {
    if (link.hash === `#${key}`) link.setAttribute("aria-current", "step");
    else link.removeAttribute("aria-current");
  }
  storyLabel.textContent = scene.title;
  storyPlatform.textContent = scene.video
    ? (scene.phone ? "Mac uygulaması ve iPhone taslağı" : "Mac uygulaması")
    : (scene.phone ? "Mac ve iPhone ekran taslakları" : "Mac ekran taslağı");
  storyLink.href = `https://www.figma.com/design/UenSgbySVClALNNAwbcg50/Full-Time?node-id=${scene.node}`;
  void setScene(story, key, animate);
}

for (const link of document.querySelectorAll(".chapter-nav a, .example-card")) {
  link.addEventListener("click", () => selectChapter(link.hash.slice(1)));
}

const navLinks = [...document.querySelectorAll(".landing-nav nav a")];
const navSections = navLinks.map(link => document.querySelector(link.hash));
let scrollFrame = 0;
let navIndex = -1;

function updateScroll() {
  scrollFrame = 0;
  const viewport = innerHeight;
  const storyBounds = stepSection.getBoundingClientRect();
  const activeLine = narrow.matches
    ? Math.min(viewport * .8, Math.max(viewport * .42, storyPanel.getBoundingClientRect().bottom + 64))
    : viewport * .47;

  let active = steps[0];
  for (const step of steps) {
    if (step.getBoundingClientRect().top > activeLine) break;
    active = step;
  }
  selectChapter(active.id);
  const progress = Math.max(0, Math.min(1, (activeLine - storyBounds.top) / (storyBounds.height || 1)));
  storyPanel.style.setProperty("--story-progress", progress);
  const pageTravel = Math.max(1, root.scrollHeight - viewport);
  root.style.setProperty("--page-progress", Math.max(0, Math.min(1, scrollY / pageTravel)));

  let currentNav = -1;
  for (const [i, section] of navSections.entries()) {
    if (section.getBoundingClientRect().top <= viewport * .28) currentNav = i;
  }
  if (currentNav !== navIndex) {
    navIndex = currentNav;
    for (const [i, link] of navLinks.entries()) {
      if (i === currentNav) link.setAttribute("aria-current", "location");
      else link.removeAttribute("aria-current");
    }
  }
  if (heroVisible) {
    heroReel.style.setProperty("--hero-drift", root.dataset.motion === "on" && !hero.static ? `${Math.min(scrollY * .105, 62)}px` : "0px");
  }
}

function queueScrollUpdate() {
  if (!scrollFrame) scrollFrame = requestAnimationFrame(updateScroll);
}

function resizeStory() {
  const offset = narrow.matches ? Math.round(storyPanel.offsetHeight + 14) : 0;
  stepSection.style.setProperty("--chapter-offset", `${offset}px`);
  queueScrollUpdate();
}

addEventListener("scroll", queueScrollUpdate, { passive: true });
addEventListener("resize", resizeStory, { passive: true });
new ResizeObserver(resizeStory).observe(storyPanel);

const reveal = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (!entry.isIntersecting) continue;
    entry.target.classList.add("shown");
    reveal.unobserve(entry.target);
  }
}, { rootMargin: "0px 0px 30px", threshold: .09 });
for (const element of document.querySelectorAll(".reveal")) reveal.observe(element);

const activeVisuals = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    const visible = entry.isIntersecting;
    entry.target.classList.toggle("active-visual", visible);
    const stage = [hero, story].find(item => item.node === entry.target);
    if (stage) {
      if (visible) playVisible(stage);
      else settleStage(stage);
    }
    if (entry.target === hero.node) {
      heroVisible = visible;
      updateHeroTimer();
    }
  }
}, { threshold: .16 });
function playVisible(stage) {
  if (!stage.static && root.dataset.motion === "on" && stage.ready && !stage.played && stage.node.classList.contains("active-visual")) {
    animateStage(stage, stage.ready, sceneDefinitions[stage.ready]);
  }
}
for (const stage of [hero, story]) activeVisuals.observe(stage.node);
activeVisuals.observe(document.querySelector(".transfer-map"));

const rail = document.querySelector(".example-rail");
const railControls = document.querySelector(".rail-controls");
const [previous, next] = railControls.querySelectorAll("button");
function updateRail() {
  const end = Math.max(0, rail.scrollWidth - rail.clientWidth);
  previous.disabled = rail.scrollLeft < 3;
  next.disabled = rail.scrollLeft > end - 3;
}
for (const button of [previous, next]) {
  button.addEventListener("click", () => {
    const distance = rail.firstElementChild.getBoundingClientRect().width + (parseFloat(getComputedStyle(rail).columnGap) || 0);
    rail.scrollBy({ left: Number(button.dataset.railDir) * distance, behavior: root.dataset.motion === "on" ? "smooth" : "instant" });
  });
}
rail.addEventListener("scroll", updateRail, { passive: true });
new ResizeObserver(updateRail).observe(rail);
railControls.hidden = false;
updateRail();


// ---- Hero: the whole app flow as one 3x recording, with a backup progress panel.
// Segment starts (seconds) match assets/recordings/flow.mp4.
var heroFlowOn = !hero.static && Boolean(hero.video && document.querySelector("[data-flow-desktop]"));
const flow = {
  src: "assets/recordings/flow.mp4",
  poster: "assets/recordings/flow-poster.jpg",
  live: [2.8, 7.38],
  segments: [
    { key: "kurulum", start: 0, intro: true },
    { key: "kurulum", start: 1.55 },
    { key: "canli-yedekleme", start: 2.8 },
    { key: "koruma", start: 7.38 },
    { key: "baglanti", start: 8.63 },
    { key: "gecmis", start: 9.88 },
  ],
  desk: document.querySelector("[data-flow-desktop]"),
  panel: document.querySelector("[data-flow-panel]"),
  pct: document.querySelector("[data-flow-pct]"),
  left: document.querySelector("[data-flow-left]"),
  bar: document.querySelector("[data-flow-bar]"),
  file: document.querySelector("[data-flow-file]"),
  current: -1,
  frame: 0,
};

function flowSegmentAt(t) {
  let index = 0;
  for (const [i, seg] of flow.segments.entries()) if (t >= seg.start) index = i;
  return index;
}

function flowApply(index) {
  flow.current = index;
  const seg = flow.segments[index];
  const scene = sceneDefinitions[seg.key];
  hero.node.dataset.scene = seg.key;
  hero.ready = seg.key;
  loadImage(scene.phone).then((image) => {
    if (flow.current !== index) return;
    if (image) hero.phone.src = image.src;
    hero.phone.hidden = !image;
    hero.node.toggleAttribute("data-single-device", !image);
  });
  hero.title.textContent = seg.intro ? "NoNeedCloud" : scene.cue;
  hero.detail.textContent = seg.intro ? "Uygulama açılıyor" : scene.detail;
  hero.number.textContent = "";
  hero.meter.hidden = seg.key !== "canli-yedekleme";
  for (const button of heroButtons) button.setAttribute("aria-pressed", String(!seg.intro && button.dataset.heroScene === seg.key));
}

function flowTick() {
  flow.frame = 0;
  const t = hero.video.currentTime;
  const index = flowSegmentAt(t);
  if (index !== flow.current) flowApply(index);
  const [a, b] = flow.live;
  const live = t >= a && t < b;
  flow.panel.classList.toggle("open", t >= a + 0.25 && t < b - 0.3);
  if (live) {
    const pct = Math.round(3 + ((t - a) / (b - a)) * 55);
    flow.pct.textContent = `%${pct}`;
    flow.left.textContent = `${Math.max(0, Math.round(320 * (1 - pct / 100)))} öğe kaldı`;
    flow.bar.style.width = `${pct}%`;
    flow.file.textContent = `IMG_${4010 + Math.round((t - a) * 23)}.HEIC`;
    hero.number.textContent = `%${pct}`;
    hero.node.style.setProperty("--meter", `${pct}%`);
  }
  if (!hero.video.paused) flow.frame = requestAnimationFrame(flowTick);
}

function flowLayout() {
  const box = hero.video.getBoundingClientRect();
  const host = hero.devices.getBoundingClientRect();
  if (!box.width || !box.height) return;
  const scale = Math.min(box.width / 1600, box.height / 1018);
  const w = 1600 * scale, h = 1018 * scale;
  Object.assign(flow.desk.style, {
    left: `${box.left - host.left + (box.width - w) / 2}px`,
    top: `${box.top - host.top + (box.height - h) / 2}px`,
    width: `${w}px`, height: `${h}px`, fontSize: `${w / 100}px`,
  });
}

function flowSelect(index, animate) {
  heroIndex = index;
  const key = heroButtons[index].dataset.heroScene;
  const seg = flow.segments.find(item => item.key === key && !item.intro);
  if (animate && seg) {
    hero.video.currentTime = seg.start + 0.05;
    playVideo(hero);
  }
  flowTick();
}

if (heroFlowOn) {
  const video = hero.video;
  hero.mac.hidden = true;
  video.hidden = false;
  video.poster = flow.poster;
  video.setAttribute("src", flow.src);
  video.setAttribute("aria-label", "NoNeedCloud Mac uygulamasının 3 kat hızlı kaydı: açılış, kurulum, yedekleme, yedek durumu, bağlantı sorunu ve geçmiş.");
  flow.desk.hidden = false;
  video.addEventListener("play", () => { cancelAnimationFrame(flow.frame); flow.frame = requestAnimationFrame(flowTick); });
  video.addEventListener("seeked", flowTick);
  video.addEventListener("loadedmetadata", () => { flowLayout(); flowTick(); });
  new ResizeObserver(flowLayout).observe(hero.devices);
  flowApply(0);
}

function openDecision() {
  if (location.hash === "#kararlar") document.getElementById("kararlar").open = true;
}
addEventListener("hashchange", openDecision);
openDecision();
selectHero(0, false);
const requestedChapter = location.hash.slice(1);
selectChapter(steps.some(step => step.id === requestedChapter) ? requestedChapter : steps[0].id, false);
setMotion();
resizeStory();
