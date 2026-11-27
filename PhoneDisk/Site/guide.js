"use strict";

const steps = [
  {
    id: "iphone", title: "Установите «Мой диск» на iPhone",
    text: "В «Моём диске» нажмите «Добавить компьютер». Если приложение уже подключено к ПК, эта кнопка находится в меню.",
    button: "Скачать на iPhone", waiting: "Участники внутреннего тестирования могут установить приложение через TestFlight. Публичная ссылка появится после выпуска."
  },
  {
    id: "windows", title: "Установите «Мой диск» на Windows",
    text: "Откройте установщик и нажмите «Установить». После установки откроется окно «Мой диск».",
    button: "Скачать для Windows", waiting: "Публичный установщик Windows готовится к выпуску.",
    note: "Если страница открыта на iPhone, зайдите на rynpro.ru/disk/ с компьютера."
  },
  {
    id: "folder", title: "Выберите папку на компьютере",
    text: "В «Моём диске» на ПК нажмите «Добавить папку» и выберите, например, «Видео». Файлы останутся на своих местах.",
    path: ["Мой диск", "Добавить папку", "Видео"],
    note: "При необходимости выберите отдельную папку для автокопий с iPhone."
  },
  {
    id: "pair", title: "Подключите iPhone по QR-коду",
    text: "На ПК нажмите «Подключить телефон». На iPhone откройте приложение «Мой диск», нажмите «Добавить компьютер» → «Сканировать QR-код» и наведите сканер на код с монитора.",
    path: ["Добавить компьютер", "Сканировать QR-код"],
    note: "Подключите оба устройства к одной домашней сети и разрешите «Локальную сеть» на iPhone. Если Windows попросит разрешить подключения, выберите частную сеть. После сканирования папка появится в «Файлах»."
  }
];
const byId = id => document.getElementById(id);
const downloads = window.phoneDiskDownloads ?? {};
let current = -1;
byId("demo").href = downloads.demo || "./demo/";

function show(index, focus = false) {
  current = index;
  byId("start").hidden = index >= 0;
  byId("guide").hidden = index < 0;
  if (index < 0) {
    if (focus) byId("begin").focus();
    return;
  }
  const step = steps[index];
  for (const button of byId("steps").querySelectorAll("button")) {
    if (Number(button.dataset.step) === index) button.setAttribute("aria-current", "step");
    else button.removeAttribute("aria-current");
  }
  byId("progress").textContent = `Шаг ${index + 1} из ${steps.length}`;
  byId("step-title").textContent = step.title;
  byId("description").textContent = step.text;
  const example = byId("example");
  example.replaceChildren();
  if (step.path) {
    const row = document.createElement("div");
    row.className = "path";
    for (const label of step.path) {
      const text = document.createElement("span");
      text.textContent = label;
      row.append(text);
    }
    example.append(row);
  }
  if (step.note) {
    const note = document.createElement("p");
    note.textContent = step.note;
    example.append(note);
  }
  byId("install").hidden = !step.button;
  const download = byId("download");
  const url = downloads[step.id];
  download.hidden = !step.button || !url;
  download.textContent = step.button ?? "";
  if (url) download.href = url;
  else download.removeAttribute("href");
  byId("availability").textContent = step.button && !url ? step.waiting : "";
  byId("back").textContent = index ? "Назад" : "На главную";
  byId("next").textContent = index === steps.length - 1 ? "На главную" : "Дальше";
  if (focus) byId("step-title").focus({ preventScroll: true });
}

function select(index) {
  const hash = index >= 0 ? "#" + steps[index].id : "";
  history.pushState(null, "", location.pathname + location.search + hash);
  show(index, true);
  window.scrollTo(0, 0);
}

function restore() {
  show(steps.findIndex(step => location.hash.slice(1) === step.id));
}

byId("begin").onclick = () => select(0);
byId("back").onclick = () => select(current - 1);
byId("next").onclick = () => select(current === steps.length - 1 ? -1 : current + 1);
byId("steps").onclick = event => {
  const target = event.target.closest("button[data-step]");
  if (target) select(Number(target.dataset.step));
};
window.addEventListener("popstate", restore);
window.addEventListener("hashchange", () => {
  const index = steps.findIndex(step => location.hash.slice(1) === step.id);
  if (index !== current) show(index, true);
});
restore();
