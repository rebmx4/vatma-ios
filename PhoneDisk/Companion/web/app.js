"use strict";

const byId = id => document.getElementById(id);
const panel = byId("panel");
const viewer = byId("viewer");
const menu = byId("menu");
const actions = byId("actions");
const state = { tab: "files", roots: [], source: null, path: "/", revision: 0, signature: "", pending: false };

function bridge(message) {
  window.webkit?.messageHandlers.phoneDiskNative.postMessage(message);
}

function element(tag, cls, text) {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text) node.textContent = text;
  return node;
}

function button(text, run, cls = "") {
  const item = element("button", cls, text);
  item.type = "button";
  item.addEventListener("click", run);
  return item;
}

function locationURL(endpoint, path, source = state.source) {
  return endpoint + "?" + new URLSearchParams({ source, path });
}

async function json(path, options = {}) {
  const response = await fetch(path, { cache: "no-store", ...options });
  if (response.status === 401) {
    bridge("access-revoked");
    throw new Error("Доступ к компьютеру закрыт.");
  }
  if (!response.ok) throw new Error("Не удалось открыть данные. Проверьте доступ к папке.");
  return response.status === 204 ? null : response.json();
}

function status(text) {
  const message = element("p", "notice", text);
  message.setAttribute("role", "status");
  panel.replaceChildren(message);
}

function setMenu(visible) {
  menu.hidden = !visible;
  byId("settings").setAttribute("aria-expanded", String(visible));
}

function navigate(source, path) {
  state.source = source;
  state.path = path;
  state.signature = "";
  window.scrollTo(0, 0);
  refresh();
}

window.phoneDiskHostSelectTab = function (tab) {
  if (tab === state.tab) return;
  if (viewer.open) viewer.close();
  setMenu(false);
  state.tab = tab;
  state.signature = "";
  refresh();
};

function rootFor(source) { return state.roots.find(root => root.source === source); }

function toolbar() {
  const root = rootFor(state.source);
  byId("title").textContent = state.tab === "backup" ? "Автокопии" :
    root ? state.path === "/" ? root.name : state.path.split("/").at(-1) : "Папки";
  panel.setAttribute("aria-label", byId("title").textContent);
  byId("back").hidden = state.tab !== "files" || !root;
  byId("upload").hidden = state.tab !== "files" || !root?.permissions.includes("create");
}

async function refresh(silent = false) {
  if (silent && (state.pending || actions.open || viewer.open || !menu.hidden || document.hidden)) return;
  const revision = ++state.revision;
  state.pending = true;
  try {
    if (state.tab === "backup") {
      const data = await json("/api/v2/backup-settings");
      if (revision !== state.revision) return;
      toolbar();
      renderIfChanged(data, renderBackups);
    } else {
      const catalog = await json("/api/companion/catalog");
      if (revision !== state.revision) return;
      state.roots = catalog.roots;
      const root = rootFor(state.source);
      if (state.source && !root) { state.source = null; state.path = "/"; }
      toolbar();
      if (!root) renderIfChanged(catalog.roots, renderRoots);
      else if (!root.available) {
        state.signature = "";
        status("Папка недоступна. Проверьте, подключён ли диск к ПК.");
      } else {
        const data = await json(locationURL("/api/companion/catalog", state.path));
        if (revision !== state.revision) return;
        renderIfChanged([root, state.path, data.items], () => renderFiles(data.items, root));
      }
    }
  } catch (error) {
    if (revision === state.revision) {
      state.signature = "";
      status(error.message);
    }
  } finally {
    if (revision === state.revision) state.pending = false;
  }
}

function renderIfChanged(data, render) {
  const value = JSON.stringify(data);
  if (state.signature === value) return;
  state.signature = value;
  render(data);
}

function renderRoots(roots) {
  if (!roots.length) { status("Добавьте доступные папки на компьютере."); return; }
  const list = element("div", "folder-list");
  for (const root of roots) {
    const row = button("", () => navigate(root.source, "/"), "root");
    row.disabled = !root.available;
    const name = element("span", "", root.name);
    if (!root.available) name.append(element("small", "", "Диск недоступен"));
    row.append(element("span", "folder-glyph"), name, element("span", "", "›"));
    list.append(row);
  }
  panel.replaceChildren(list);
}

function formatBytes(bytes) {
  if (bytes === 0) return "0 Б";
  const units = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
  const power = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
  return new Intl.NumberFormat("ru", { maximumFractionDigits: 1 }).format(bytes / 1024 ** power) + " " + units[power];
}

function renderFiles(items, root) {
  if (!items.length) { status("Папка пуста"); return; }
  const list = element("div", "file-grid");
  for (const file of items) {
    const tile = button("", () => file.directory ? navigate(root.source, file.path) :
      file.playable ? viewFile(file, root) : fileActions(file, root), "tile");
    const art = element("span", "art", file.media === "video" ? "▶" : file.directory ? "" : "▤");
    if (file.directory) art.append(element("span", "folder-glyph"));
    if (file.media) {
      const image = document.createElement("img");
      image.alt = "";
      image.loading = "lazy";
      image.src = locationURL("/api/companion/cover", file.path, root.source);
      image.addEventListener("error", () => image.remove(), { once: true });
      art.append(image);
      if (file.media === "video") art.append(element("span", "video-mark", "▶"));
    }
    const text = element("span", "caption");
    text.append(element("span", "", file.name));
    if (!file.directory) text.append(element("small", "", formatBytes(file.size)));
    tile.append(art, text);
    if (!file.directory) tile.addEventListener("contextmenu", event => { event.preventDefault(); fileActions(file, root); });
    list.append(tile);
  }
  panel.replaceChildren(list);
}

function download(file, root) {
  bridge({ action: "download", source: root.source, path: file.path, name: file.name });
}

function viewFile(file, root) {
  byId("file-title").textContent = file.name;
  const control = byId("download");
  control.hidden = !root.permissions.includes("download");
  control.onclick = () => download(file, root);
  const media = document.createElement(file.media === "video" ? "video" : "img");
  if (file.media === "video") {
    media.controls = true;
    media.playsInline = true;
    media.preload = "metadata";
    media.poster = locationURL("/api/companion/cover", file.path, root.source);
  } else media.alt = file.name;
  media.src = locationURL("/api/companion/media", file.path, root.source);
  media.addEventListener("error", () => {
    byId("media").replaceChildren(element("p", "notice", "Этот файл не удалось открыть."));
  }, { once: true });
  byId("media").replaceChildren(media);
  viewer.showModal();
  if (file.media === "video") media.play().catch(() => {});
}

function showActions(title, controls) {
  byId("action-title").textContent = title;
  byId("action-buttons").replaceChildren(...controls);
  if (!actions.open) actions.showModal();
}

function fileActions(file, root) {
  const controls = [];
  if (file.playable) controls.push(button("Открыть", () => { actions.close(); viewFile(file, root); }));
  if (root.permissions.includes("delete")) controls.push(button("Удалить", () => showActions("Переместить в корзину?", [
    button("Удалить", async () => {
      try { await json(locationURL("/api/companion/trash", file.path, root.source), { method: "POST" }); actions.close(); refresh(); }
      catch (error) { showActions(error.message, []); }
    }, "danger")
  ]), "danger"));
  if (root.permissions.includes("download")) controls.push(button("Скачать", () => { actions.close(); download(file, root); }));
  showActions(file.name, controls);
}

function renderBackups(backup) {
  const list = element("div");
  for (const [type, title] of [["photo", "Фото с телефона"], ["video", "Видео с телефона"]]) {
    const current = backup[type];
    const row = element("div", "backup-row");
    const label = element("label", "", title);
    const toggle = document.createElement("input");
    toggle.type = "checkbox";
    toggle.id = "auto-" + type;
    toggle.setAttribute("role", "switch");
    toggle.checked = current.enabled;
    toggle.disabled = !current.source;
    label.htmlFor = toggle.id;
    label.append(element("small", "", current.source ? current.label + current.path : "Выберите папку для автокопий на ПК."));
    toggle.addEventListener("change", async () => {
      const enabled = toggle.checked;
      toggle.disabled = true;
      try {
        const updated = await json("/api/companion/backups", {
          method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ type, enabled })
        });
        bridge({ action: "backup-settings", enabled: String(enabled) });
        renderIfChanged(updated, renderBackups);
      } catch (error) { toggle.checked = !enabled; showActions(error.message, []); }
      finally { toggle.disabled = false; }
    });
    row.append(label, toggle);
    if (current.source) row.append(button("Пробная выгрузка", () =>
      bridge({ action: "upload", source: current.source, path: current.path, type })));
    list.append(row);
  }
  panel.replaceChildren(list);
}

function upload() {
  bridge({ action: "upload", source: state.source, path: state.path, type: "files" });
}

byId("close-viewer").onclick = () => viewer.close();
viewer.addEventListener("close", () => byId("media").replaceChildren());
byId("settings").onclick = () => setMenu(menu.hidden);
byId("lock").onclick = () => { setMenu(false); bridge("face-settings"); };
byId("disconnect").onclick = () => { setMenu(false); bridge("unpair"); };
byId("refresh").onclick = () => refresh();
byId("upload").onclick = upload;
byId("back").onclick = () => {
  const parent = state.path.substring(0, state.path.lastIndexOf("/")) || "/";
  navigate(state.path === "/" ? null : state.source, parent);
};
document.addEventListener("click", event => { if (!event.target.closest("#toolbar")) setMenu(false); });
document.addEventListener("contextmenu", event => event.preventDefault());

let press = null;
let pressAt = null;
function endPress() { clearTimeout(press); press = null; pressAt = null; }
panel.addEventListener("pointerdown", event => {
  if (state.tab !== "files" || event.target.closest("button") || !event.isPrimary || event.button !== 0) return;
  pressAt = [event.clientX, event.clientY];
  press = setTimeout(() => { endPress(); setMenu(true); }, 1000);
});
panel.addEventListener("pointermove", event => {
  if (pressAt && Math.hypot(event.clientX - pressAt[0], event.clientY - pressAt[1]) > 10) endPress();
});
for (const name of ["pointerup", "pointercancel", "pointerleave"]) document.addEventListener(name, endPress);
document.addEventListener("scroll", endPress, { passive: true });
setInterval(() => refresh(true), 6000);
refresh();
