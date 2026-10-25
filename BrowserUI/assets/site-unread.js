(() => {
  const host = location.hostname.toLowerCase();
  const provider = ['vk.com', 'vk.ru'].some(domain => host === domain || host.endsWith(`.${domain}`)) ? 'vk'
    : host === 'avito.ru' || host.endsWith('.avito.ru') ? 'avito' : null;
  if (!provider || !document.querySelectorAll) return null;

  const messagePath = provider === 'vk'
    ? /^\/(?:im|mail|messenger)(?:\/|$)/i
    : /(?:^|\/)messenger(?:\/|$)|(?:^|\/)messages(?:\/|$)/i;
  const number = value => {
    const match = String(value || '').trim().match(/^(\d{1,3})\+?$/);
    return match ? Math.min(999, Number(match[1])) : null;
  };
  const unreadLabel = value => {
    const label = String(value || '').toLowerCase();
    if (!/(?:unread|new messages|непрочит|новых сообщен)/i.test(label)) return null;
    const match = label.match(/(?:^|\D)(\d{1,3})\+?(?:\D|$)/);
    return match ? Math.min(999, Number(match[1])) : null;
  };
  let found = false;
  const counts = [];
  const candidates = 'a[href*="/im"], a[href*="/mail"], a[href*="messenger"], a[href*="messages"]';
  for (const link of Array.from(document.querySelectorAll(candidates)).slice(0, 100)) {
    let target;
    try { target = new URL(link.getAttribute('href'), location.href); } catch { continue; }
    if (target.hostname.toLowerCase() !== host || !messagePath.test(target.pathname)) continue;
    if (provider === 'vk' && target.searchParams.has('sel')) continue;
    if (provider === 'avito' && /(?:chat|dialog)/i.test(target.search)) continue;
    const children = Array.from(link.querySelectorAll('[aria-label], [class], [data-testid]')).slice(0, 35);
    const isNavigation = Boolean(link.closest('header, nav, aside, [role="navigation"]'));
    const marked = children.filter(node => {
      const marker = `${typeof node.className === 'string' ? node.className : ''} ${node.getAttribute('data-testid') || ''} ${node.getAttribute('aria-label') || ''}`;
      return /(?:counter|badge|unread|count|непрочит)/i.test(marker);
    });
    if (!isNavigation && !marked.length) continue;
    found = true;
    const labels = [link.getAttribute('aria-label'), ...marked.map(node => node.getAttribute('aria-label'))];
    for (const label of labels) {
      const value = unreadLabel(label);
      if (value !== null) counts.push(value);
    }
    for (const node of marked) {
      const value = number(node.textContent);
      if (value !== null) counts.push(value);
    }
    if (!marked.length) {
      const text = String(link.textContent || '').trim();
      if (text.length <= 40 && /(?:сообщения|мессенджер|messages)/i.test(text)) {
        const match = text.match(/(?:^|\D)(\d{1,3})\+?\s*$/);
        if (match) counts.push(Math.min(999, Number(match[1])));
      }
    }
  }
  return found ? { provider, count: counts.length ? Math.max(...counts) : 0 } : null;
})()
