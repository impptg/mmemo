'use strict';
function heartInterval(level) { return [0,25000,20000,15000,10000,7000,4000,2000,1000,600,300][level]; }
function heartCount(level) { return Math.ceil(level/3); }
if (typeof module !== 'undefined') module.exports = { heartInterval, heartCount };
if (typeof window !== 'undefined') {
  let level = 0, timer = null;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  function spawn() {
    if (document.body.childElementCount > 12) return;
    const heart = document.createElement('span'); heart.className = 'heart';
    heart.style.setProperty('--size', `${12 + Math.random()*7}px`);
    heart.style.setProperty('--drift', `${-12-Math.random()*34}px`);
    heart.innerHTML = '<svg viewBox="0 0 64 64" aria-hidden="true"><path d="M31 54C24 50 7 37 8 23C9 9 25 7 32 21C42 6 58 14 56 28C54 40 40 49 31 54Z" fill="#ff9a98" stroke="#e97879" stroke-width="4" stroke-linejoin="round"/><path d="M17 20Q13 25 18 30" fill="none" stroke="#ffe7db" stroke-width="5" stroke-linecap="round"/></svg>';
    document.body.append(heart);
    heart.addEventListener('animationend', () => heart.remove(), {once:true});
  }
  function tick() {
    for(let i=0;i<(reduced.matches ? 1 : heartCount(level));i++) spawn();
    if (!reduced.matches) timer = setTimeout(tick, heartInterval(level));
  }
  window.hearts = { update(value) {
    value=Number.isInteger(value) ? Math.max(0,Math.min(10,value)) : 0;
    if (value === level) return;
    level = value; clearTimeout(timer); document.querySelectorAll('.heart').forEach(h => h.remove());
    if (level > 0) tick();
  }};
  reduced.addEventListener('change', () => { const value=level; level=-1; window.hearts.update(value); });
  // Explicit standalone preview; the desktop never sets this query parameter.
  if (location.search === '?preview') window.hearts.update(10);
}
