export function displayGeometry(width, height, orientation) {
  const degrees = { landscape_left: 90, landscape_right: -90, portrait_upside_down: 180 }[orientation] ?? 0;
  return Math.abs(degrees) === 90 ? { width: height, height: width, degrees } : { width, height, degrees };
}
export function rawPoint(orientation, x, y) {
  if (orientation === 'landscape_left') return { x: y, y: 1 - x };
  if (orientation === 'landscape_right') return { x: 1 - y, y: x };
  if (orientation === 'portrait_upside_down') return { x: 1 - x, y: 1 - y };
  return { x, y };
}
export function fitFrame(width, height, availableWidth, availableHeight, border) {
  const scale = Math.max(.01, Math.min((availableWidth - 2 * border) / width, (availableHeight - 2 * border) / height));
  return { width: width * scale + 2 * border, height: height * scale + 2 * border };
}
