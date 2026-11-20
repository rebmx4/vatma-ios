export function selectAddressOnFirstTap(input, clearButton) {
  let selectOnClick = false;
  let lastEditingTap;
  let selectionFrame;
  const cancelSelection = () => {
    if (selectionFrame !== undefined) cancelAnimationFrame(selectionFrame);
    selectionFrame = undefined;
  };
  const selectAll = () => {
    if (!input.value || input.ownerDocument.activeElement !== input) return;
    input.select();
    // WebKit can place the caret after the focus or tap handler.
    cancelSelection();
    selectionFrame = requestAnimationFrame(() => {
      selectionFrame = undefined;
      if (input.ownerDocument.activeElement === input && input.value) input.select();
    });
  };

  input.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    cancelSelection();
    selectOnClick = input.ownerDocument.activeElement !== input;
  });
  input.addEventListener('focus', () => {
    lastEditingTap = undefined;
    selectAll();
  });
  input.addEventListener('pointerup', event => {
    if (event.pointerType === 'touch' && selectOnClick) selectAll();
  });
  input.addEventListener('click', event => {
    if (selectOnClick) {
      selectOnClick = false;
      selectAll();
      return;
    }
    if (event.detail === 0) return;
    const tap = { time: event.timeStamp, x: event.clientX, y: event.clientY };
    if (lastEditingTap && tap.time - lastEditingTap.time <= 380 &&
        Math.hypot(tap.x - lastEditingTap.x, tap.y - lastEditingTap.y) <= 24) {
      lastEditingTap = undefined;
      selectAll();
    } else {
      lastEditingTap = tap;
    }
  });
  for (const type of ['blur', 'input', 'pointercancel', 'keydown']) {
    input.addEventListener(type, () => {
      cancelSelection();
      selectOnClick = false;
      lastEditingTap = undefined;
    });
  }
  const keepInputFocused = event => {
    if (input.ownerDocument.activeElement === input) event.preventDefault();
  };
  clearButton.addEventListener('pointerdown', keepInputFocused);
  clearButton.addEventListener('mousedown', keepInputFocused);
  clearButton.addEventListener('click', () => {
    input.focus({preventScroll: true});
    input.value = '';
    input.dispatchEvent(new Event('input', {bubbles: true}));
  });
}
