export function messageProvider(value) {
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:') return null;
    const host = url.hostname.toLowerCase();
    if (['vk.com', 'vk.ru'].some(domain => host === domain || host.endsWith(`.${domain}`))) return 'vk';
    if (host === 'avito.ru' || host.endsWith('.avito.ru')) return 'avito';
  } catch {}
  return null;
}

export function messagesEnabled(app) {
  if (!app || app.type === 'system' || !messageProvider(app.url)) return false;
  return app.messageNotifications === true ||
    (app.messageNotifications !== false && ['vk', 'avito'].includes(app.id));
}

export function enabledMessageProviders(items) {
  const providers = new Set();
  const visit = item => {
    if (Array.isArray(item.children)) item.children.forEach(visit);
    else if (messagesEnabled(item)) providers.add(messageProvider(item.url));
  };
  items.forEach(visit);
  return [...providers].sort();
}

export function shortcutMessageCount(app, scope, counts) {
  if (scope === 'private') return 0;
  if (app.id === 'atma-home') return Object.values(counts).reduce((sum, count) => sum + count, 0);
  if (Array.isArray(app.children)) {
    return enabledMessageProviders(app.children).reduce((sum, provider) => sum + (counts[provider] || 0), 0);
  }
  return messagesEnabled(app) ? counts[messageProvider(app.url)] || 0 : 0;
}

export function badgeLabel(count) { return count > 99 ? '99+' : String(count); }
