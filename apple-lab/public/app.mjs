import { deviceInput } from './input.mjs';
const $ = selector => document.querySelector(selector);
const csrf = $('meta[name="lab-csrf"]').content;
const canvas = $('#screen'), frame = $('#device-frame'), context = canvas.getContext('2d', { alpha: false });
let socket, device = 'iphone', state = { phase: 'idle', connected: false, active: false }, lastDraw = 0, lastState = 0, latest, drawing = false, toastTimer;
async function api(path, value = {}) {
  const response = await fetch('/api/' + path, { method: 'POST', headers: { 'content-type': 'application/json', 'x-lab-csrf': csrf }, body: JSON.stringify(value) });
  const data = await response.json(); if (!response.ok) throw new Error(data.error || 'Операция не выполнена'); return data;
}
function toast(message) { $('#toast').textContent = message; $('#toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => { $('#toast').hidden = true; }, 8000); }
function fit() {
  const stage = $('.stage'), ratio = canvas.width / canvas.height;
  const width = Math.min(stage.clientWidth - 36, (stage.clientHeight - 28) * ratio);
  frame.style.width = Math.max(100, width) + 'px'; frame.style.height = Math.max(100, width / ratio) + 'px';
}
new ResizeObserver(fit).observe($('.stage'));
function usable() { return state.connected && socket?.readyState === WebSocket.OPEN && Date.now() - lastState < 6000 && Date.now() - lastDraw < 8000; }
function render() {
  const live = usable(), pending = state.active && !live, stopping = state.phase === 'stopping';
  $('#connection').classList.toggle('live', live);
  $('#connection span').textContent = live ? 'Связь установлена' : stopping ? 'Отключение…' : pending ? 'Подключение…' : 'Нет подключения';
  const button = $('#connect'); button.classList.toggle('live', live); button.classList.toggle('pending', pending || stopping);
  button.disabled = socket?.readyState !== WebSocket.OPEN || stopping;
  button.lastElementChild.textContent = live ? 'Отключить' : stopping ? 'Отключаем…' : pending ? 'Отменить подключение' : 'Подключить';
  for (const choice of document.querySelectorAll('.device-choice')) choice.disabled = state.active || stopping;
  for (const control of document.querySelectorAll('[data-control]')) control.disabled = !live;
  $('#status').textContent = state.message || 'Нет подключения';
  $('#revision').textContent = state.revision?.slice(0, 12) ?? '—';
  $('#resolution').textContent = state.config ? `${state.config.width} × ${state.config.height} px` : '—';
  $('#run-link').hidden = !state.runUrl;
  if (state.runUrl) $('#run-link').href = state.runUrl;
  $('#placeholder').hidden = !!(lastDraw && state.active && Date.now() - lastDraw < 8000);
  $('#spinner').hidden = !pending;
  $('#placeholder-title').textContent = stopping ? 'Отключаем устройство' : pending ? 'Готовим устройство' : state.phase === 'error' ? 'Сеанс остановлен' : 'Готов к подключению';
  $('#placeholder-copy').textContent = pending ? 'Первый запуск займёт несколько минут.\nMac собирает приложение.' : state.phase === 'error' ? state.message : 'Выберите устройство и нажмите «Подключить».';
  const remaining = Math.max(0, (state.deadline ?? 0) - Date.now());
  $('#timer').textContent = state.active && state.deadline ? `Осталось ${Math.floor(remaining / 60000)}:${String(Math.floor(remaining / 1000) % 60).padStart(2, '0')}` : pending ? 'Подготовка сеанса' : 'Сеанс не запущен';
}
function select(value) {
  device = value; frame.classList.toggle('tablet', value === 'ipad'); frame.classList.toggle('phone', value === 'iphone');
  if (!state.active) { canvas.width = value === 'ipad' ? 1032 : 440; canvas.height = value === 'ipad' ? 1376 : 956; }
  $('#device-title').textContent = value === 'ipad' ? 'iPad' : 'iPhone';
  for (const choice of document.querySelectorAll('.device-choice')) {
    const selected = choice.dataset.device === value; choice.classList.toggle('selected', selected); choice.setAttribute('aria-pressed', String(selected));
  }
  fit();
}
async function draw() {
  if (drawing) return; drawing = true;
  while (latest) {
    const data = latest; latest = null;
    try {
      const sequence = new DataView(data).getUint32(0);
      const bitmap = await createImageBitmap(new Blob([data.slice(4)], { type: 'image/jpeg' }));
      if (canvas.width !== bitmap.width || canvas.height !== bitmap.height) { canvas.width = bitmap.width; canvas.height = bitmap.height; fit(); }
      context.drawImage(bitmap, 0, 0); bitmap.close(); lastDraw = Date.now();
      if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'paint', sequence }));
      render();
    } catch { /* An incomplete frame does not count as a live connection. */ }
  }
  drawing = false;
}
function connectPanel() {
  socket = new WebSocket(`${location.origin.replace('http:', 'ws:')}/live?csrf=${csrf}`); socket.binaryType = 'arraybuffer';
  socket.onopen = render;
  socket.onmessage = event => {
    if (typeof event.data !== 'string') { latest = event.data; void draw(); return; }
    const value = JSON.parse(event.data);
    if (value.type === 'state') { state = value; lastState = Date.now(); if (state.active && state.device !== device) select(state.device); if (!state.active) lastDraw = 0; render(); }
  };
  socket.onclose = () => { state.connected = false; state.active = false; state.message = 'Панель отключена. Обновите окно для нового подключения'; lastDraw = 0; render(); };
  socket.onerror = () => { state.connected = false; render(); };
}
for (const choice of document.querySelectorAll('.device-choice')) choice.onclick = () => select(choice.dataset.device);
$('#connect').onclick = async () => {
  $('#connect').disabled = true;
  try { state = await api(state.active ? 'stop' : 'start', { device }); lastState = Date.now(); render(); }
  catch (error) { toast(error.message); render(); }
};
const dialog = $('#text-dialog');
function openPaste() { dialog.showModal(); $('#text-value').focus(); }
const controls = deviceInput(canvas, { connected: usable, send: data => { if (socket.readyState === WebSocket.OPEN) socket.send(data); }, paste: openPaste });
let landscape = false;
for (const button of document.querySelectorAll('[data-control]')) button.onclick = async () => {
  try {
    const action = button.dataset.control;
    if (action === 'home') controls.home();
    if (action === 'rotate') { landscape = !landscape; controls.rotate(landscape ? 'landscape_left' : 'portrait'); }
    if (action === 'text') openPaste();
    if (action === 'relaunch') await api('action', { type: 'relaunch' });
    if (action === 'capture') toast('Снимок сохранён: ' + (await api('capture')).path);
    canvas.focus();
  } catch (error) { toast(error.message); }
};
$('#paste-text').onclick = async () => {
  try { await api('action', { type: 'text', text: $('#text-value').value }); dialog.close(); canvas.focus(); }
  catch (error) { toast(error.message); }
};
setInterval(render, 1000); select(device); connectPanel();
