// Opt-in throughput comparison in the existing LOCAL test folder.
(() => {
  const main = document.getElementById('main');
  if (!main) return;
  const testFolder = '/Wi-Fi-test-63';
  const testFile = testFolder + '/Wi-Fi-3GB-LAN.bin';
  const sample = 96 * 1024 * 1024;
  const localHeaders = {'X-PhoneDisk-Local-Only': '1'};

  function mount() {
    if (currentTab !== 'files' || folder?.source !== 'photos-c' || folder.path !== testFolder ||
        main.querySelector('[data-test-streams]')) return;
    const heading = main.querySelector('.files-toolbar');
    if (!heading) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.testStreams = '';
    button.textContent = 'Сравнить 1 и 10 потоков';
    button.addEventListener('click', compare);
    heading.after(button);
  }

  async function readSample(url, etag, size, count, offset, signal) {
    const started = performance.now();
    const parts = Array.from({length: count}, async (_, index) => {
      const start = offset + Math.floor(sample * index / count);
      const end = offset + Math.floor(sample * (index + 1) / count);
      const response = await fetch(url, {credentials: 'same-origin', cache: 'no-store', signal,
        headers: {...localHeaders, Range: 'bytes=' + start + '-' + (end - 1), 'If-Range': etag}});
      if (response.status !== 206 || response.headers.get('ETag') !== etag ||
          response.headers.get('Content-Range') !== 'bytes ' + start + '-' + (end - 1) + '/' + size) {
        await response.body?.cancel();
        throw Error('Диапазон файла недоступен по домашней сети.');
      }
      const reader = response.body.getReader();
      let received = 0;
      try {
        for (;;) {
          const {done, value} = await reader.read();
          if (done) break;
          received += value.byteLength;
        }
      } finally { reader.releaseLock(); }
      if (received !== end - start) throw Error('Получена неполная часть файла.');
    });
    await Promise.all(parts);
    return (performance.now() - started) / 1000;
  }

  async function compare() {
    if (document.getElementById('wifi-stream-comparison')) return;
    const dialog = document.createElement('dialog');
    dialog.id = 'wifi-stream-comparison';
    dialog.setAttribute('aria-label', 'Сравнение потоков');
    dialog.innerHTML = '<h2>Скорость по Wi‑Fi</h2><p role="status" aria-live="polite"></p><button type="button">Остановить</button>';
    document.body.append(dialog);
    const status = dialog.querySelector('p');
    const close = dialog.querySelector('button');
    const controller = new AbortController();
    const {signal} = controller;
    const hidden = () => { if (document.hidden) controller.abort(); };
    const timeout = setTimeout(() => controller.abort(), 180000);
    document.addEventListener('visibilitychange', hidden);
    close.addEventListener('click', () => dialog.close());
    dialog.addEventListener('close', () => { controller.abort(); dialog.remove(); }, {once: true});
    dialog.showModal();
    status.textContent = 'Проверяю подключение к ПК…';
    try {
      const capabilities = await fetch('/api/v2/capabilities', {cache: 'no-store', signal});
      if (!capabilities.ok || (await capabilities.json()).lan !== true) throw Error('Для сравнения подключись к домашнему Wi‑Fi.');
      const url = '/api/v2/file?' + new URLSearchParams({source: 'photos-c', path: testFile});
      const header = await fetch(url, {method: 'HEAD', headers: localHeaders, cache: 'no-store', signal});
      const etag = header.headers.get('ETag');
      const size = Number(header.headers.get('X-File-Size'));
      if (!header.ok || size !== 3000000000 || !etag) throw Error('Тестовый файл недоступен.');
      const results = {1: 0, 10: 0};
      const sequence = [1, 10, 10, 1];
      for (const [i, count] of sequence.entries()) {
        status.textContent = 'Замер ' + (i + 1) + ' из 4 · ' + (count === 1 ? '1 поток' : '10 потоков') + '. Оставь экран открытым.';
        const offset = i < 2 ? 0 : sample;
        results[count] += await readSample(url, etag, size, count, offset, signal);
      }
      const mbps = count => 2 * sample / 1000000 / results[count];
      const fmt = number => number.toLocaleString('ru-RU', {maximumFractionDigits: 2});
      status.textContent = '1 поток — ' + fmt(mbps(1)) + ' МБ/с. 10 потоков — ' + fmt(mbps(10)) + ' МБ/с.';
    } catch (error) {
      status.textContent = signal.aborted ? 'Замер прерван. Запусти его ещё раз на открытом экране.' : error.message;
    } finally {
      controller.abort();
      clearTimeout(timeout);
      document.removeEventListener('visibilitychange', hidden);
      close.textContent = 'Готово';
    }
  }

  new MutationObserver(mount).observe(main, {childList: true});
  mount();
})();
