function duration(ms) { const seconds = Math.max(0, Math.floor(ms / 1000)); return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`; }
export function sessionView(state, { now = Date.now(), live = false } = {}) {
  if (state.phase === 'stopping') return { button: 'Отключаем…', title: 'Завершаем сеанс',
    copy: 'Останавливаем задачу на Mac. После подтверждения остановки можно подключиться снова.', timer: 'Остановка сеанса…' };
  if (live) return { button: 'Отключить', title: '', copy: '', timer: `Осталось ${duration((state.deadline ?? now) - now)}` };
  if (state.active) return { button: 'Отменить запуск', title: state.message || 'Готовим устройство…',
    copy: state.progressHint || 'Подключаем экран и управление. Дождитесь появления устройства.',
    timer: `Подготовка · ${duration(now - (state.startedAt ?? now))}` };
  return { button: 'Подключить', title: state.phase === 'error' ? 'Сеанс остановлен' : 'Готов к подключению',
    copy: state.phase === 'error' ? state.message : 'Выберите устройство и нажмите «Подключить».\nПервый запуск занимает несколько минут.', timer: 'Сеанс не запущен' };
}
