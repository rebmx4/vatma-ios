export function addressSuggestions(input, state, shortcuts = []) {
  const query = input.trim();
  if (!query) return [];
  const needle = query.toLocaleLowerCase();
  const active = state?.tabs?.find(tab => tab.id === state.activeTabId);
  const isPrivate = state?.privateBrowsing === true;
  const results = [];
  const seen = new Set();

  function match(entry, kind) {
    if (results.length === 4 || !entry.url) return;
    let url;
    try { url = new URL(entry.url); } catch { return; }
    if (!['http:', 'https:'].includes(url.protocol) || seen.has(url.href)) return;
    const title = entry.title || entry.name || url.hostname;
    if (![title, url.href].some(value => value.toLocaleLowerCase().includes(needle))) return;
    seen.add(url.href);
    results.push({kind, entry, title, detail: url.hostname});
  }

  for (const tab of state?.tabs || []) {
    if (tab.id === active?.id) continue;
    const sameSession = active?.privateSessionID && tab.privateSessionID === active.privateSessionID;
    if (isPrivate ? tab.privateBrowsing === true && sameSession : !tab.privateBrowsing && !tab.privateDesktop) {
      match(tab, 'tab');
    }
  }
  if (!isPrivate) {
    for (const shortcut of shortcuts) match(shortcut, 'shortcut');
  }

  // Address-looking input uses the normal navigation action.
  if (!/^[^.:\s]+:/.test(query) && (/\s/.test(query) || (!query.includes('.') && !query.startsWith('localhost')))) {
    results.push({kind: 'search', query});
  }
  return results;
}

export function installAddressSuggestions(input, list, options) {
  const {suggest, select, searchLabel, editing} = options;
  let results = [];
  let selectedIndex = -1;

  function clear() {
    results = [];
    selectedIndex = -1;
    list.hidden = true;
    list.replaceChildren();
  }

  function choose(index) {
    const result = results[index];
    if (!result) return;
    clear();
    input.blur();
    select(result);
  }

  input.addEventListener('input', () => {
    clear();
    if (input.ownerDocument.activeElement !== input) return;
    results = suggest(input.value);
    for (const [index, match] of results.entries()) {
      const button = input.ownerDocument.createElement('button');
      button.type = 'button';
      button.className = 'address-suggestion';
      button.textContent = match.kind === 'search' ? searchLabel(match.query) : match.title;
      if (match.detail && match.detail !== match.title) {
        const detail = input.ownerDocument.createElement('small');
        detail.textContent = match.detail;
        button.append(detail);
      }
      button.addEventListener('pointerdown', event => event.preventDefault());
      button.addEventListener('mousedown', event => event.preventDefault());
      button.addEventListener('click', () => choose(index));
      list.append(button);
    }
    list.hidden = results.length === 0;
  });
  input.addEventListener('focus', () => editing(true));
  input.addEventListener('blur', event => {
    editing(false);
    if (!list.contains(event.relatedTarget)) clear();
  });
  list.addEventListener('focusout', event => {
    if (!list.contains(event.relatedTarget)) clear();
  });
  input.addEventListener('keydown', event => {
    if (!results.length || event.isComposing) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      clear();
    } else if (event.key === 'Enter' && selectedIndex >= 0) {
      event.preventDefault();
      choose(selectedIndex);
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const delta = event.key === 'ArrowDown' ? 1 : -1;
      selectedIndex = (selectedIndex < 0 && delta < 0)
        ? results.length - 1 : (selectedIndex + delta + results.length) % results.length;
      for (const [index, button] of [...list.children].entries()) {
        button.classList.toggle('selected', index === selectedIndex);
      }
      list.children[selectedIndex]?.scrollIntoView({block: 'nearest'});
    }
  });
  return clear;
}
