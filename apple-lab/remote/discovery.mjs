export function helperOrigin(payload, simulator) {
  const streams = payload?.running ? payload.streams ?? [payload] : [];
  const state = streams.find(value => value.device === simulator);
  if (!state || !Number.isInteger(state.port) || state.port < 1024 || state.port > 65535) throw new Error('No selected Simulator stream port');
  const stream = new URL(state.streamUrl), ws = new URL(state.wsUrl);
  const allowedPath = ['', `/helper/${simulator}`];
  const base = stream.pathname.replace(/\/stream\.mjpeg$/, '');
  const local = url => ['127.0.0.1', 'localhost'].includes(url.hostname) && Number(url.port) === state.port && !url.username && !url.password && !url.search && !url.hash;
  if (stream.protocol !== 'http:' || ws.protocol !== 'ws:' || !local(stream) || !local(ws) ||
      !allowedPath.includes(base) || stream.pathname !== base + '/stream.mjpeg' || ws.pathname !== base + '/ws') throw new Error('Invalid Simulator stream URLs');
  return `http://127.0.0.1:${state.port}${base}`;
}
