// Theme choice, the hero's entrance, and dithered plates developing as they scroll in. Nothing is tracked.
(function () {
  var root = document.documentElement;
  root.classList.add('js');

  var stored = null;
  try { stored = localStorage.getItem('sower-theme'); } catch (e) {}
  if (stored === 'light' || stored === 'dark') root.setAttribute('data-theme', stored);

  function current() {
    var chosen = root.getAttribute('data-theme');
    if (chosen) return chosen;
    return window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  function sync() {
    var theme = current();
    document.querySelectorAll('[data-theme-choice]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.getAttribute('data-theme-choice') === theme));
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('[data-theme-choice]').forEach(function (b) {
      b.addEventListener('click', function () {
        var theme = b.getAttribute('data-theme-choice');
        root.setAttribute('data-theme', theme);
        try { localStorage.setItem('sower-theme', theme); } catch (e) {}
        sync();
      });
    });
    if (window.matchMedia) matchMedia('(prefers-color-scheme: dark)').addEventListener('change', sync);
    sync();

    var word = document.querySelector('.hero-word');
    if (word && !word.dataset.split) {
      var text = word.textContent;
      word.setAttribute('aria-label', text);
      word.textContent = '';
      Array.prototype.forEach.call(text, function (ch, i) {
        var span = document.createElement('span');
        span.textContent = ch;
        span.setAttribute('aria-hidden', 'true');
        span.style.setProperty('--i', i);
        word.appendChild(span);
      });
      word.dataset.split = '1';
    }

    var plates = document.querySelectorAll('.develop');
    if ('IntersectionObserver' in window) {
      var seen = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) { e.target.classList.add('in'); seen.unobserve(e.target); }
        });
      }, { rootMargin: '0px 0px -8% 0px' });
      plates.forEach(function (p) { seen.observe(p); });
    } else {
      plates.forEach(function (p) { p.classList.add('in'); });
    }
  });
})();
