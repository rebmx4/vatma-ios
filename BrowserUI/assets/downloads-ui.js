// Keep the action buttons in place while WebKit reports new byte counts.
export function renderTransfers(root, tasks, labels, formatSize, perform, openTab) {
  const visible = tasks.filter(task => task.status !== 'done');
  root.hidden = visible.length === 0;
  const active = visible.filter(task => ['connecting','running','cancelling'].includes(task.status)).length;
  let heading = root.querySelector('h3');
  if (!heading) { heading = document.createElement('h3'); root.append(heading); }
  heading.textContent = active ? labels.count + ' · ' + active : labels.downloads;
  const rows = new Map([...root.querySelectorAll('[data-transfer]')].map(row => [row.dataset.transfer,row]));
  for (const task of visible) {
    let row = rows.get(task.id);
    if (!row) {
      row = document.createElement('article');
      row.dataset.transfer = task.id;
      row.innerHTML = '<strong data-no-translate></strong><small></small><progress></progress><div class="transfer-actions"></div>';
      root.append(row);
    }
    rows.delete(task.id);
    const [name,detail,progress,actions] = row.children;
    name.textContent = task.name;
    const working = task.status === 'running';
    const known = task.total > 0;
    const percent = known ? Math.min(100, Math.floor(100 * task.received / task.total)) : 0;
    detail.textContent = working ? (known ? percent+'% · '+formatSize(task.received)+' / '+formatSize(task.total) : formatSize(task.received)) :
      task.status === 'confirm' ? (task.total >= 0 ? formatSize(task.total) : labels.unknown) :
      task.error || labels[task.status] || labels.cancel;
    progress.hidden = !working;
    progress.max = 100;
    if (known) progress.value = percent; else progress.removeAttribute('value');
    progress.setAttribute('aria-label',task.name);
    const key = JSON.stringify([task.status,task.retry,task.canOpen,labels.save]);
    if (row.dataset.controls === key) continue;
    row.dataset.controls = key;
    actions.replaceChildren();
    function button(label, handler) {
      const item = document.createElement('button');
      item.type = 'button'; item.textContent = label;
      item.onclick = async () => {
        item.disabled = true;
        try { await handler(); } finally { item.disabled = false; }
      };
      actions.append(item);
    }
    if (task.status === 'confirm') button(labels.save,()=>perform('confirm',task.id));
    if (['confirm','connecting','running'].includes(task.status)) button(labels.cancel,()=>perform('cancel',task.id));
    if (['failed','cancelled'].includes(task.status)) {
      if (task.retry) button(labels.retry,()=>perform('retry',task.id));
      else if (task.canOpen) button(labels.openTab,()=>openTab(task.tabID));
      button(labels.delete,()=>perform('remove',task.id));
    }
  }
  for (const row of rows.values()) row.remove();
}
