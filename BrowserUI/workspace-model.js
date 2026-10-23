export const isFolder = entry => entry?.type === 'folder';
export const flattenApps = entries => entries.flatMap(entry => isFolder(entry) ? entry.children : [entry]);
export function arrangeEntries(entries, columns = 4) {
  const taken=new Set(), slots=new Map();
  for(const entry of entries) {
    const slot=entry.slots?.[columns];
    if(Number.isInteger(slot)&&slot>=0&&slot<10000&&!taken.has(slot)) {slots.set(entry.id,slot);taken.add(slot);}
  }
  let cursor=0;
  return entries.map(entry=>{
    if(!slots.has(entry.id)){while(taken.has(cursor))cursor++;slots.set(entry.id,cursor);taken.add(cursor++);}
    return{entry,slot:slots.get(entry.id)};
  });
}
export function freezeSlots(entries, columns = 4) {
  const items=structuredClone(entries);
  for(const {entry,slot} of arrangeEntries(items,columns))entry.slots={...entry.slots,[columns]:slot};
  return items;
}
export function placeEntry(entries, id, slot, columns = 4) {
  if(!Number.isInteger(slot)||slot<0||slot>=10000)return{items:entries,changed:false};
  const items=freezeSlots(entries,columns), source=findEntry(items,id);
  if(!source)return{items:entries,changed:false};
  const occupant=items.find(item=>item.id!==id&&item.slots[columns]===slot);
  if(occupant) {
    const occupied=new Set(items.map(item=>item.slots[columns]));let free=0;while(occupied.has(free))free++;
    occupant.slots[columns]=source.parent?free:source.entry.slots[columns];
  }
  source.entry.slots={...source.entry.slots,[columns]:slot};
  if(source.parent){source.list.splice(source.index,1);items.push(source.entry);}
  return{items:items.filter(item=>!isFolder(item)||item.children.length),changed:true};
}
export function findEntry(entries, id) {
  for (let index = 0; index < entries.length; index++) {
    const entry = entries[index];
    if (entry.id === id) return { entry, list: entries, index, parent: null };
    if (isFolder(entry)) {
      const child = entry.children.findIndex(item => item.id === id);
      if (child >= 0) return { entry: entry.children[child], list: entry.children, index: child, parent: entry };
    }
  }
  return null;
}
export function dropEntry(entries, sourceId, targetId, options = {}) {
  const items = options.columns ? freezeSlots(entries, options.columns) : structuredClone(entries);
  const source = findEntry(items, sourceId), target = targetId ? findEntry(items, targetId) : null;
  const unchanged = () => ({ items: entries, changed: false });
  if (!source || sourceId === targetId || (targetId && !target)) return unchanged();
  const destination = options.destinationFolderId ? findEntry(items, options.destinationFolderId)?.entry : null;
  if (options.destinationFolderId && (!isFolder(destination) || isFolder(source.entry))) return unchanged();
  if (target?.parent && target.parent !== destination) return unchanged();
  let folderId;
  if (options.combine && target && !target.parent && !isFolder(source.entry) && !destination) {
    source.list.splice(source.index, 1);
    if (isFolder(target.entry)) {
      target.entry.children.push(source.entry);
      folderId = target.entry.id;
    } else {
      folderId = options.newFolderId || `folder-${crypto.randomUUID()}`;
      const index = items.findIndex(item => item.id === targetId);
      items.splice(index, 1, { id: folderId, type: 'folder', name: 'Папка', slots:target.entry.slots, children: [target.entry, source.entry] });
    }
  } else {
    const list = destination ? destination.children : items;
    if (target && target.list !== list) return unchanged();
    const index = target ? target.index : list.length;
    source.list.splice(source.index, 1);
    list.splice(Math.min(index, list.length), 0, source.entry);
  }
  const result = items.filter(item => !isFolder(item) || item.children.length);
  return { items: result, changed: JSON.stringify(result) !== JSON.stringify(entries), folderId };
}
export function removeEntry(entries, id) {
  const items = structuredClone(entries), found = findEntry(items, id);
  if (!found) return entries;
  found.list.splice(found.index, 1, ...(isFolder(found.entry) ? found.entry.children : []));
  return items.filter(item => !isFolder(item) || item.children.length);
}
