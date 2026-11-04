export function selectAddressOnFirstTap(input) {
  let beganUnfocused = false;
  input.addEventListener('pointerdown', () => {
    beganUnfocused = input.ownerDocument.activeElement !== input;
  });
  input.addEventListener('focus', () => {
    if (input.value) input.select();
  });
  input.addEventListener('click', () => {
    if (beganUnfocused && input.value) input.select();
    beganUnfocused = false;
  });
  for (const event of ['blur', 'pointercancel']) {
    input.addEventListener(event, () => { beganUnfocused = false; });
  }
}
