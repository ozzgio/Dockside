'use strict';
const palettes = {
  midnight: ['#091020', '#ffffff', '#c4d5eb', '#add9ff'],
  ocean: ['#092638', '#ffffff', '#c4d5eb', '#add9ff'],
  paper: ['#f4f7fc', '#10192a', '#454d61', '#254cad'],
  graphite: ['#202024', '#ffffff', '#c4d5eb', '#add9ff'],
  forest: ['#0b3024', '#ffffff', '#c4d5eb', '#96efb8'],
  plum: ['#35213b', '#ffffff', '#c4d5eb', '#e8baff'],
  sunset: ['#ffe8d6', '#10192a', '#454d61', '#8c2e1f']
};
const preview = document.querySelector('#preview');
for (const button of document.querySelectorAll('[data-theme]')) {
  button.addEventListener('click', () => {
    const palette = palettes[button.dataset.theme];
    if (!palette) return;
    ['--bg', '--fg', '--muted', '--accent'].forEach((property, index) => preview.style.setProperty(property, palette[index]));
    document.querySelectorAll('[data-theme]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
  });
}
