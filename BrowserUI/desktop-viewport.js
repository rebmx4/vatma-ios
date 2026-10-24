export function observeDesktopViewport(target, render) {
  const observer = new ResizeObserver(render);
  observer.observe(target);
  window.addEventListener('resize', render);
  return () => {
    observer.disconnect();
    window.removeEventListener('resize', render);
  };
}
