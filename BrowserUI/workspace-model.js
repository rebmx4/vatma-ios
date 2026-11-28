export const isFolder = entry => entry?.type === 'folder';
export const flattenApps = entries => entries.flatMap(entry => isFolder(entry) ? entry.children : [entry]);
export const DOCK_SIZE = 4;
export const MAX_DESKTOP_PAGES = 10;
export const FOLDER_PAGE_SIZE = 9;
export const MAX_FOLDER_SHORTCUTS = FOLDER_PAGE_SIZE * 5;

export function desktopPageCount(layout, capacity) {
  const lastSlot=layout.reduce((last,{slot})=>Math.max(last,slot),-1);
  return Math.max(1,Math.ceil((lastSlot+1)/capacity));
}

export function arrangeDock(entries) {
  const dock = Array(DOCK_SIZE).fill(null);
  for (const entry of entries) {
    const slot = entry.dockSlot;
    if (Number.isInteger(slot) && slot >= 0 && slot < dock.length && !dock[slot]) dock[slot] = entry;
  }
  return dock;
}

export function arrangeEntries(entries, columns = 4) {
  const docked = new Set(arrangeDock(entries));
  const grid = entries.filter(entry => !docked.has(entry));
  const taken=new Set(), slots=new Map();
  for(const entry of grid) {
    const slot=entry.slots?.[columns];
    if(Number.isInteger(slot)&&slot>=0&&slot<10000&&!taken.has(slot)) {slots.set(entry.id,slot);taken.add(slot);}
  }
  let cursor=0;
  return grid.map(entry=>{
    if(!slots.has(entry.id)){while(taken.has(cursor))cursor++;slots.set(entry.id,cursor);taken.add(cursor++);}
    return{entry,slot:slots.get(entry.id)};
  });
}
export function shiftEntriesToOppositeEdge(entries, columns, capacity) {
  if(!Number.isInteger(capacity)||capacity<columns||capacity%columns)return{items:entries,changed:false};
  const items=freezeSlots(entries,columns),grid=arrangeEntries(items,columns),pages=new Map(),rows=capacity/columns;
  for(const {slot} of grid){
    const page=Math.floor(slot/capacity),row=Math.floor((slot%capacity)/columns);
    const bounds=pages.get(page)||{first:row,last:row};
    bounds.first=Math.min(bounds.first,row);bounds.last=Math.max(bounds.last,row);pages.set(page,bounds);
  }
  let changed=false;
  for(const {entry,slot} of grid){
    const bounds=pages.get(Math.floor(slot/capacity));
    const topSpace=bounds.first,bottomSpace=rows-1-bounds.last;
    const offset=(topSpace<bottomSpace?bottomSpace:-topSpace)*columns;
    if(offset){entry.slots[columns]=slot+offset;changed=true;}
  }
  return{items,changed};
}
export function collapseSingletonFolders(items) {
  return items.flatMap(item=>{
    if(!isFolder(item))return[item];
    if(item.children.length>1)return[item];
    if(!item.children.length)return[];
    const child={...item.children[0],slots:{...item.children[0].slots,...item.slots}};
    if(Number.isInteger(item.dockSlot))child.dockSlot=item.dockSlot;
    else delete child.dockSlot;
    return[child];
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
  const grid=arrangeEntries(items,columns), dockSlot=arrangeDock(items).indexOf(source.entry);
  const occupant=grid.find(position=>position.entry.id!==id&&position.slot===slot)?.entry;
  if(occupant) {
    if(dockSlot>=0)occupant.dockSlot=dockSlot;
    else occupant.slots[columns]=source.parent?firstFreeSlot(grid):source.entry.slots[columns];
  }
  delete source.entry.dockSlot;
  source.entry.slots={...source.entry.slots,[columns]:slot};
  if(source.parent){source.list.splice(source.index,1);items.push(source.entry);}
  return{items:collapseSingletonFolders(items),changed:true};
}

function firstFreeSlot(grid) {
  const occupied = new Set(grid.map(position => position.slot));
  let slot = 0;
  while (occupied.has(slot)) slot++;
  return slot;
}

export function placeDockEntry(entries, id, slot, columns = 4) {
  if (!Number.isInteger(slot) || slot < 0 || slot >= DOCK_SIZE) return {items:entries, changed:false};
  const items = freezeSlots(entries, columns), source = findEntry(items, id);
  if (!source) return {items:entries, changed:false};
  const dock = arrangeDock(items), sourceSlot = dock.indexOf(source.entry), occupant = dock[slot];
  if (sourceSlot === slot) return {items:entries, changed:false};
  if (occupant) {
    if (sourceSlot >= 0) occupant.dockSlot = sourceSlot;
    else {
      const gridSlot = source.parent ? firstFreeSlot(arrangeEntries(items, columns)) : source.entry.slots[columns];
      delete occupant.dockSlot;
      occupant.slots = {...occupant.slots, [columns]:gridSlot};
    }
  }
  source.entry.dockSlot = slot;
  if (source.parent) {
    source.list.splice(source.index, 1);
    items.push(source.entry);
  }
  return {items:collapseSingletonFolders(items), changed:true};
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
  if (destination && source.parent !== destination && destination.children.length >= MAX_FOLDER_SHORTCUTS)
    return { ...unchanged(), folderFull:true };
  if (target?.parent && target.parent !== destination) return unchanged();
  let folderId;
  if (options.combine && target && !target.parent && !isFolder(source.entry) && !destination) {
    if (source.parent === target.entry) return unchanged();
    if (isFolder(target.entry) && target.entry.children.length >= MAX_FOLDER_SHORTCUTS)
      return { ...unchanged(), folderFull:true };
    source.list.splice(source.index, 1);
    delete source.entry.dockSlot;
    if (isFolder(target.entry)) {
      target.entry.children.push(source.entry);
      folderId = target.entry.id;
    } else {
      folderId = options.newFolderId || `folder-${crypto.randomUUID()}`;
      const index = items.findIndex(item => item.id === targetId);
      const {dockSlot, slots} = target.entry;
      delete target.entry.dockSlot;
      items.splice(index, 1, {
        id: folderId, type: 'folder', name: options.newFolderName || 'Папка',
        slots, dockSlot, children: [target.entry, source.entry]
      });
    }
  } else {
    const list = destination ? destination.children : items;
    if (target && target.list !== list) return unchanged();
    const index = target ? target.index : list.length;
    source.list.splice(source.index, 1);
    list.splice(Math.min(index, list.length), 0, source.entry);
  }
  const result = collapseSingletonFolders(items);
  return { items: result, changed: JSON.stringify(result) !== JSON.stringify(entries), folderId };
}
export function removeEntry(entries, id) {
  const items = structuredClone(entries), found = findEntry(items, id);
  if (!found) return entries;
  const children=isFolder(found.entry)?found.entry.children:[];
  if(children.length&&Number.isInteger(found.entry.dockSlot))children[0].dockSlot=found.entry.dockSlot;
  found.list.splice(found.index, 1, ...children);
  return collapseSingletonFolders(items);
}
