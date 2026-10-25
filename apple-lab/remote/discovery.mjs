export function helperOrigin(payload, simulator) {
  const streams = payload?.running ? payload.streams ?? [payload] : [];
  const state = streams.find(value => value.device === simulator);
  if (!state || !Number.isInteger(state.port) || state.port < 1024 || state.port > 65535) throw new Error('No selected Simulator stream port');
  return `http://127.0.0.1:${state.port}`;
}
