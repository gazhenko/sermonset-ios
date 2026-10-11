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
    var calm = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (calm || !('IntersectionObserver' in window) || !document.body.animate) {
      plates.forEach(function (p) { p.classList.add('in'); });
      return;
    }
    var seen = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        seen.unobserve(e.target);
        loaded(e.target).then(function () { glitchIn(e.target); });
      });
    }, { threshold: 0.3 });
    // Wait for the type so nothing shifts under a plate while it's arriving.
    (document.fonts ? document.fonts.ready : Promise.resolve()).then(function () {
      plates.forEach(function (p) { seen.observe(p); });
    });
  });

  // Pictures glitch in: torn bands jump sideways, a misregistered ghost flickers, and the print
  // resolves through the same 4×4 Bayer screen the app's cards use.
  var BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  var CELL = 3;
  var screens = null;

  function screen(level) {
    if (!screens) {
      screens = [];
      var scale = Math.max(2, Math.ceil(window.devicePixelRatio || 1));
      var c = document.createElement('canvas');
      c.width = c.height = 4 * CELL * scale;
      var g = c.getContext('2d');
      for (var k = 0; k <= 16; k++) {
        g.clearRect(0, 0, c.width, c.height);
        g.fillStyle = '#000';
        for (var i = 0; i < 16; i++) {
          if (BAYER[i] < k) g.fillRect((i % 4) * CELL * scale, Math.floor(i / 4) * CELL * scale, CELL * scale, CELL * scale);
        }
        screens.push('url(' + c.toDataURL() + ')');
      }
    }
    return screens[Math.max(0, Math.min(16, level))];
  }

  function rand(a, b) { return a + Math.random() * (b - a); }
  function sign(n) { return Math.random() < 0.5 ? -n : n; }
  function shift(pct) { return 'translateX(' + pct.toFixed(2) + '%)'; }
  function band(top, height) { return 'inset(' + top.toFixed(1) + '% 0 ' + Math.max(0, 100 - top - height).toFixed(1) + '% 0)'; }
  function held(frames) { frames.forEach(function (f) { f.easing = 'steps(1, end)'; }); return frames; }

  function maskOf(el) {
    var cs = getComputedStyle(el);
    var m = cs.maskImage && cs.maskImage !== 'none' ? cs.maskImage : cs.webkitMaskImage;
    return m && m !== 'none' ? m : null;
  }

  function loaded(el) {
    var src = el.tagName === 'IMG' ? el.currentSrc || el.src : (/url\(["']?(.*?)["']?\)/.exec(maskOf(el) || '') || [])[1];
    if (!src) return Promise.resolve();
    var img = el.tagName === 'IMG' ? el : new Image();
    if (img !== el) img.src = src;
    if (img.decode) return img.decode().catch(function () {});
    return new Promise(function (done) { if (img.complete) done(); else img.onload = img.onerror = done; });
  }

  function glitchIn(plate) {
    var r = plate.getBoundingClientRect();
    if (!r.width || !r.height) { plate.classList.add('in'); return; }
    var T = 900;
    var cs = getComputedStyle(plate);
    var isImg = plate.tagName === 'IMG';
    var mask = maskOf(plate);
    var std = window.CSS && CSS.supports && CSS.supports('mask-composite', 'intersect');

    // Overlay pieces live in a full-width layer that clips sideways, so a torn band never widens the page.
    var pad = r.height * 0.1;
    var layer = document.createElement('div');
    layer.className = 'glitch';
    layer.setAttribute('aria-hidden', 'true');
    layer.style.top = (r.top + window.scrollY - pad) + 'px';
    layer.style.height = (r.height + pad * 2) + 'px';
    document.body.appendChild(layer);

    function piece() {
      var d;
      if (isImg) {
        d = plate.cloneNode(false);
        d.removeAttribute('loading');
        d.removeAttribute('class');
        d.alt = '';
        d.style.borderRadius = cs.borderRadius;
        d.style.border = cs.border;
      } else {
        d = document.createElement('div');
        d.className = Array.prototype.filter.call(plate.classList, function (c) { return c === 'art' || c.indexOf('art-') === 0; }).join(' ');
        d.style.background = cs.backgroundColor;
      }
      d.style.left = r.left + 'px';
      d.style.top = pad + 'px';
      d.style.width = r.width + 'px';
      d.style.height = r.height + 'px';
      d.style.opacity = '0';
      layer.appendChild(d);
      return d;
    }

    // The plate itself: flashes in pieces, sits off register, blinks once, then holds.
    var a = sign(rand(1.5, 4));
    plate.classList.add('in');
    var runs = [];
    runs.push(plate.animate(held([
      { offset: 0, opacity: 0, transform: 'none', clipPath: 'inset(0 0 0 0)' },
      { offset: 0.06, opacity: 1, transform: shift(a), clipPath: band(rand(5, 50), rand(12, 30)) },
      { offset: 0.14, opacity: 0, transform: 'none', clipPath: 'inset(0 0 0 0)' },
      { offset: 0.22, opacity: 1, transform: shift(-a / 2), clipPath: 'inset(0 0 ' + rand(35, 60).toFixed(1) + '% 0)' },
      { offset: 0.34, opacity: 1, transform: shift(a / 3), clipPath: 'inset(' + rand(20, 45).toFixed(1) + '% 0 0 0)' },
      { offset: 0.44, opacity: 1, transform: 'none', clipPath: 'inset(0 0 0 0)' },
      { offset: 0.62, opacity: 1, transform: shift(-a / 4), clipPath: 'inset(0 0 0 0)' },
      { offset: 0.68, opacity: 1, transform: 'none', clipPath: 'inset(0 0 0 0)' },
      { offset: 0.8, opacity: 0, transform: 'none', clipPath: 'inset(0 0 0 0)' },
      { offset: 0.84, opacity: 1, transform: 'none', clipPath: 'inset(0 0 0 0)' },
      { offset: 1, opacity: 1, transform: 'none', clipPath: 'inset(0 0 0 0)' }
    ]), { duration: T }));

    // Torn bands of the print, knocked sideways.
    for (var i = 0; i < 7; i++) {
      var s = piece();
      var clip = band(rand(0, 94), rand(1.5, 10));
      var t0 = rand(0.03, 0.55), t1 = t0 + rand(0.04, 0.09), t2 = t1 + rand(0.04, 0.1);
      runs.push(s.animate(held([
        { offset: 0, opacity: 0, transform: 'none', clipPath: clip },
        { offset: t0, opacity: 1, transform: shift(sign(rand(2, 7))), clipPath: clip },
        { offset: t1, opacity: 1, transform: shift(sign(rand(0.8, 3))), clipPath: clip },
        { offset: Math.min(t2, 0.9), opacity: 0, transform: 'none', clipPath: clip },
        { offset: 1, opacity: 0, transform: 'none', clipPath: clip }
      ]), { duration: T }));
    }

    // A second pass printed off register.
    var g = piece(), gx = sign(rand(0.8, 1.6));
    runs.push(g.animate(held([
      { offset: 0, opacity: 0, transform: 'none' },
      { offset: 0.06, opacity: 0.4, transform: shift(gx) },
      { offset: 0.2, opacity: 0, transform: 'none' },
      { offset: 0.28, opacity: 0.35, transform: shift(-gx) },
      { offset: 0.5, opacity: 0.3, transform: shift(gx / 2) },
      { offset: 0.66, opacity: 0, transform: 'none' },
      { offset: 1, opacity: 0, transform: 'none' }
    ]), { duration: T }));

    // Meanwhile the print resolves dot by dot through the Bayer screen, stuttering once.
    var size = isImg ? '' : cs.maskSize || cs.webkitMaskSize;
    var pos = isImg ? '' : cs.maskPosition || cs.webkitMaskPosition;
    var tile = 4 * CELL + 'px ' + 4 * CELL + 'px';
    function apply(level) {
      var img = mask ? mask + ', ' + screen(level) : screen(level);
      var props = {
        Image: img,
        Size: mask ? size + ', ' + tile : tile,
        Position: mask ? pos + ', 0 0' : '0 0',
        Repeat: mask ? 'no-repeat, repeat' : 'repeat'
      };
      Object.keys(props).forEach(function (k) {
        if (std) plate.style['mask' + k] = props[k]; else plate.style['webkitMask' + k] = props[k];
      });
      if (mask) { if (std) plate.style.maskComposite = 'intersect'; else plate.style.webkitMaskComposite = 'source-in'; }
    }
    function clear() {
      ['Image', 'Size', 'Position', 'Repeat', 'Composite'].forEach(function (k) {
        plate.style['mask' + k] = '';
        plate.style['webkitMask' + k] = '';
      });
    }
    var start = performance.now(), stutter = rand(0.3, 0.5), last = -1;
    function tick(now) {
      var p = Math.min(1, (now - start) / (T * 0.78));
      var level = Math.round(2 + 14 * p * p);
      if (p > stutter && p < stutter + 0.08) level = Math.max(2, level - 5);
      if (level !== last) { apply(level); last = level; }
      if (p < 1) requestAnimationFrame(tick); else clear();
    }
    apply(2);
    requestAnimationFrame(tick);

    // Whatever happens to the clock (a throttled tab, a stalled frame), the picture ends up printed.
    setTimeout(function () {
      runs.forEach(function (run) { try { run.finish(); } catch (e) {} });
      layer.remove();
      clear();
    }, T + 60);
  }
})();
