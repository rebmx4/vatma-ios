(function () {
  const excluded = 'script, style, noscript, form, input, textarea, select, code, pre, svg, [contenteditable], [hidden], [inert], [aria-hidden="true"], [translate="no"], .notranslate';
  let pending;
  let translated = [];

  function isExcluded(element) {
    if (!element || element.closest(excluded) || !element.getClientRects().length) return true;
    const visibility = getComputedStyle(element).visibility;
    return visibility === 'hidden' || visibility === 'collapse';
  }

  function collectNodes(language, maxNodes, maxLength) {
    if (!document.body) return [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const nodes = [];
    let visited = 0;
    let length = 0;
    let node;
    while (visited < 12000 && nodes.length < maxNodes && (node = walker.nextNode())) {
      visited++;
      const original = node.data;
      const text = original.trim();
      if (!text || text.length > 4000 || !/\p{L}/u.test(text)) continue;
      const element = node.parentElement;
      if (isExcluded(element)) continue;
      const nodeLanguage = element.closest('[lang]')?.lang.toLowerCase().split(/[-_]/)[0];
      if (language && nodeLanguage && nodeLanguage !== language) continue;
      if (length + text.length > maxLength) continue;
      nodes.push({node, original, text});
      length += text.length;
    }
    return nodes;
  }

  function languageSample() {
    return {
      language: document.documentElement.lang.trim(),
      sample: collectNodes('', 40, 5000).map(({text}) => text).join(' ')
    };
  }

  function collect(ticket, source = document.documentElement.lang) {
    const language = source.trim().toLowerCase().split(/[-_]/)[0];
    const nodes = collectNodes(language, 380, 48000);
    pending = {ticket, nodes};
    return {language, texts: nodes.map(({text}) => text)};
  }

  function apply(ticket, results) {
    if (pending?.ticket !== ticket || pending.nodes.length !== results.length) return false;
    const {nodes} = pending;
    pending = undefined;
    translated = [];
    for (const [index, {node, original, text}] of nodes.entries()) {
      const result = results[index]?.trim();
      if (!result || result === text || !node.isConnected || node.data !== original || isExcluded(node.parentElement)) continue;
      const output = original.replace(text, () => result);
      node.data = output;
      translated.push({node, original, output});
    }
    return translated.length > 0;
  }

  function restore() {
    for (const {node, original, output} of translated) {
      if (node.isConnected && node.data === output) node.data = original;
    }
    translated = [];
    pending = undefined;
  }

  return {languageSample, collect, apply, restore};
})()
