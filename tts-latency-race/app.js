'use strict';
/* Fire one sentence at every configured model, draw what comes back.
   The server does the timing; this page decodes the PCM, draws it on a shared
   time axis, and plays whichever lane speaks first. */

const $ = (s) => document.querySelector(s);
const S = { lanes: {}, order: [], span: 1500, running: false, ctx: null, ranked: [], bars: false, warm: 0 };
const BIN_MS = 2;                        // one min/max envelope bin per 2 ms of audio
const MONO = 'ui-monospace, Menlo, monospace';
const JSON_H = { 'Content-Type': 'application/json' };
const DIM = 'rgba(255,255,255,.16)';
const INK = '#f4f4f2';
const dpr = () => window.devicePixelRatio || 1;
const ms = (v) => (v == null ? '–' : Math.round(v));

/* ---------------------------------------------------------------- audio
   One growing Float32Array per lane holds the whole stream. Playback schedules
   slices of it, so a replay is a single buffer and live play is one slice per
   chunk, gapless on the audio clock. */
function ctx() {
  if (!S.ctx) S.ctx = new (window.AudioContext || window.webkitAudioContext)();
  if (S.ctx.state === 'suspended') S.ctx.resume();
  return S.ctx;
}
function append(L, f) {
  if (L.pcm.length < L.n + f.length) {
    const grown = new Float32Array(Math.max(1 << 16, (L.n + f.length) * 2));
    grown.set(L.pcm.subarray(0, L.n));
    L.pcm = grown;
  }
  L.pcm.set(f, L.n);
  L.n += f.length;
  const per = Math.max(1, Math.round(L.sr * BIN_MS / 1000));
  for (; L.binned + per <= L.n; L.binned += per) {          // whole bins only, so bin i is always at i * BIN_MS
    let mn = 1, mx = -1;
    for (let j = L.binned; j < L.binned + per; j++) { const v = L.pcm[j]; if (v < mn) mn = v; if (v > mx) mx = v; }
    L.mn.push(mn); L.mx.push(mx);
  }
}
function schedule(L, f) {
  if (!f.length) return;
  const c = ctx(), buf = c.createBuffer(1, f.length, L.sr);
  buf.copyToChannel(f, 0);
  const src = c.createBufferSource();
  src.buffer = buf;
  src.connect(c.destination);
  const at = Math.max(c.currentTime + 0.02, L.next);
  src.start(at);
  L.next = at + buf.duration;
  L.nodes.push(src);
  src.onended = () => {
    L.nodes = L.nodes.filter((n) => n !== src);
    if (!L.nodes.length && L.streamDone) stop(L);           // an empty queue mid-stream is a gap, not the end
  };
}
function stop(L) {
  L.nodes.forEach((n) => { try { n.stop(); } catch (e) {} });
  L.nodes = []; L.next = 0; L.live = false;
  L.el.classList.remove('playing');
}
function play(L) {
  if (!L.n && !S.running) return;                           // nothing buffered and nothing coming
  Object.values(S.lanes).forEach(stop);
  L.live = true;                                            // live: later chunks are scheduled as they land
  L.el.classList.add('playing');
  schedule(L, L.pcm.subarray(0, L.n));                      // the winner lands before its first audio frame
}

/* ---------------------------------------------------------------- drawing */
function fit(cv) {
  const r = cv.getBoundingClientRect(), k = dpr();
  const w = Math.max(1, Math.round(r.width * k)), h = Math.max(1, Math.round(r.height * k));
  if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; }
  return cv.getContext('2d');
}
function step() {
  for (const s of [100, 200, 250, 500, 1000, 2000]) if (S.span / s <= 10) return s;
  return 5000;
}
function drawLane(L) {
  const g = fit(L.cv), W = L.cv.width, H = L.cv.height;
  const x = (t) => t / S.span * W;
  g.clearRect(0, 0, W, H);
  g.strokeStyle = 'rgba(255,255,255,.07)'; g.lineWidth = 1;   // the same grid as the ruler below
  for (let t = 0; t <= S.span; t += step()) { g.beginPath(); g.moveTo(x(t) + .5, 0); g.lineTo(x(t) + .5, H); g.stroke(); }
  if (L.arrival == null) return;
  const onset = L.arrival + (L.silence || 0);
  if (S.bars) drawBar(L, g, x, W, H, onset);
  else drawWave(L, g, x, W, H, onset);
  if (L.silence != null && onset <= S.span) {                // where the listener first hears something
    g.strokeStyle = INK; g.lineWidth = dpr();
    g.beginPath(); g.moveTo(x(onset), 0); g.lineTo(x(onset), H); g.stroke();
  }
}
function drawWave(L, g, x, W, H, onset) {
  const mid = H / 2, w = Math.max(1, x(BIN_MS));
  for (let i = 0; i < L.mn.length; i++) {
    const t = L.arrival + i * BIN_MS;
    if (t > S.span) break;
    g.fillStyle = (L.silence == null || t >= onset) ? L.color : DIM;   // dim until the voice starts
    const top = mid + Math.min(L.mn[i], 0) * mid * .92, bot = mid + Math.max(L.mx[i], 0) * mid * .92;
    g.fillRect(x(t), top, w, Math.max(1, bot - top));
  }
}
// breakdown: [network round trip | rest of the first chunk | leading silence] from
// t0 to TTFA. Faint, solid, then hatched: audio that has arrived but is not yet speech.
function drawBar(L, g, x, W, H, onset) {
  const k = dpr(), bh = Math.round(H * .62), y = Math.round((H - bh) / 2);
  const net = L.rtt != null ? Math.min(L.rtt, L.arrival) : 0;
  for (const [a, b, alpha] of [[0, net, .4], [net, L.arrival, 1], [L.arrival, onset, 0]]) {
    const xa = x(a), w = x(b) - xa;
    if (w < .5) continue;
    g.save(); g.beginPath(); g.rect(xa, y, w, bh); g.clip();
    g.fillStyle = alpha ? L.color : '#000';
    g.globalAlpha = alpha || 1;
    g.fillRect(xa, y, w, bh);
    g.globalAlpha = 1;
    if (!alpha) {                                            // hatch the silence
      g.strokeStyle = L.color; g.lineWidth = 3 * k;
      g.beginPath();
      for (let px = xa - bh; px < xa + w + bh; px += 10 * k) { g.moveTo(px, y + bh); g.lineTo(px + bh, y); }
      g.stroke();
    }
    g.restore();
    if (w >= 30 * k) {                                       // the legend names the segments, so just the number
      g.fillStyle = alpha ? '#000' : INK;
      g.font = `600 ${10 * k}px ${MONO}`; g.textAlign = 'center';
      g.fillText(ms(b - a), xa + w / 2, y + bh / 2 + 4 * k);
    }
  }
  const xe = x(onset), tot = `${ms(onset)} ms`;              // the total, just outside the bar
  g.fillStyle = INK; g.font = `700 ${15 * k}px ${MONO}`; g.textAlign = 'left';
  const tw = g.measureText(tot).width;
  g.fillText(tot, xe + 10 * k + tw > W ? xe - 10 * k - tw : xe + 10 * k, y + bh / 2 + 6 * k);
}
function drawRuler() {
  const cv = $('#ruler'), g = fit(cv), W = cv.width;
  g.clearRect(0, 0, W, cv.height);
  g.fillStyle = 'rgba(244,244,242,.45)';
  g.font = `${11 * dpr()}px ${MONO}`;
  g.textBaseline = 'top';
  for (let t = step(); t <= S.span; t += step()) {
    const x = t / S.span * W;
    g.fillRect(x, 0, 1, 4);
    g.textAlign = t === S.span ? 'right' : 'center';
    g.fillText(`${t} ms`, Math.min(x, W - 1), 6);
  }
}
// the axis frames the start of speech, not the whole utterance: ten seconds wide,
// the hundred milliseconds that separate the lanes would be invisible
function redraw() {
  const slowest = Object.values(S.lanes).reduce((m, L) => Math.max(m, L.ttfa * 1.6 || L.arrival * 1.3 || 0), 900);
  const gran = slowest <= 1500 ? 100 : (slowest <= 3000 ? 250 : 500);
  S.span = Math.min(6000, Math.ceil(slowest / gran) * gran);
  drawRuler();
  Object.values(S.lanes).forEach(drawLane);
}

/* ---------------------------------------------------------------- lanes */
function resetLane(L) {
  Object.assign(L, { pcm: new Float32Array(0), n: 0, binned: 0, mn: [], mx: [], sr: 24000,
    arrival: null, silence: null, ttfa: null, nodes: [], next: 0, live: false, streamDone: false });
  L.el.classList.remove('leader', 'playing');
  L.el.querySelector('.rank').className = 'rank';
  L.el.querySelector('.rank').textContent = '';
  L.el.querySelector('.ttfa .v').textContent = '–';
  L.el.querySelector('.err').textContent = '';
  L.el.querySelector('.modelname').hidden = false;
}
function build(cfg) {
  S.order = Object.keys(cfg.lanes);
  $('#race').innerHTML = '';
  for (const pid of S.order) {
    const c = cfg.lanes[pid];
    const el = document.createElement('div');
    el.className = 'lane' + (c.configured ? '' : ' off');
    el.dataset.lane = pid;
    el.innerHTML = `
      <div class="meta">
        <div class="name"><span class="swatch"></span>${c.label}<span class="rank"></span></div>
        <div class="modelname">${c.configured ? c.model : 'no key: set ' + c.key_env}</div>
        <div class="err"></div>
        <div class="ttfa"><span class="v">–</span><small>ms</small></div>
      </div>
      <div class="plot"><canvas></canvas></div>`;
    $('#race').appendChild(el);
    const L = S.lanes[pid] = { pid, el, cv: el.querySelector('canvas'), rtt: c.rtt_ms,
      color: getComputedStyle(el).getPropertyValue('--c').trim() };
    resetLane(L);
    el.addEventListener('click', () => { if (!S.running) play(L); });
  }
  redraw();
}
// lanes climb as they answer: whoever has spoken sits on top, in order, the rest
// keep their configured order below. FLIP, so the move is a slide and not a jump.
function reorder(first) {
  const was = Object.values(S.lanes).map((L) => [L, L.el.getBoundingClientRect().top]);
  for (const pid of [...first, ...S.order.filter((p) => !first.includes(p))]) $('#race').appendChild(S.lanes[pid].el);
  for (const [L, top] of was) {
    const dy = top - L.el.getBoundingClientRect().top;
    if (!dy) continue;
    L.el.style.cssText = `transition: none; transform: translateY(${dy}px)`;
    requestAnimationFrame(() => { L.el.style.cssText = 'transition: transform .35s cubic-bezier(.2,.7,.2,1)'; });
  }
}
function rank() {
  S.ranked.sort((a, b) => a.ttfa - b.ttfa);
  S.ranked.forEach((L, i) => {
    L.el.querySelector('.rank').className = 'rank' + (i ? '' : ' first');
    L.el.querySelector('.rank').textContent = `#${i + 1}`;
    L.el.classList.toggle('leader', i === 0);
  });
  reorder(S.ranked.map((L) => L.pid));
}

/* ---------------------------------------------------------------- the run */
function prewarm(force) {          // open the provider sockets before Go, so the race times synthesis
  if (!force && performance.now() - S.warm < 8000) return;   // under every provider's idle timeout
  S.warm = performance.now();
  fetch('/api/prewarm', { method: 'POST', headers: JSON_H, body: '{}' }).catch(() => {});
}
function onEvent(m) {
  const L = S.lanes[m.p];
  if (!L) return;
  if (m.ev === 'first') {
    L.arrival = m.arrival;
  } else if (m.ev === 'audio') {
    L.sr = m.sr || L.sr;
    const bin = atob(m.b64), f = new Float32Array(bin.length >> 1);
    for (let i = 0; i < f.length; i++) {                     // base64 to s16le to float
      const v = bin.charCodeAt(2 * i) | (bin.charCodeAt(2 * i + 1) << 8);
      f[i] = (v >= 0x8000 ? v - 0x10000 : v) / 32768;
    }
    append(L, f);
    if (L.live) schedule(L, f);
    redraw();
  } else if (m.ev === 'landed') {
    L.arrival = m.arrival; L.silence = m.silence; L.ttfa = m.ttfa;
    L.el.querySelector('.ttfa .v').textContent = ms(m.ttfa);
    S.ranked.push(L);
    rank();
    if (S.ranked.length === 1) play(L);                      // only the fastest lane is played
    redraw();
  } else if (m.ev === 'done' || m.ev === 'error') {
    L.streamDone = true;
    if (m.msg) { L.el.querySelector('.modelname').hidden = true; L.el.querySelector('.err').textContent = m.msg; }
    if (!L.nodes.length) stop(L);
  }
}
async function go(e) {
  e.preventDefault();
  const text = $('#text').value.trim();
  if (!text || S.running) return;
  S.running = true; $('#go').disabled = true;
  ctx();                                                     // open the audio context on the click, so the
  S.ranked = [];                                             // browser lets the winning lane play itself
  Object.values(S.lanes).forEach(resetLane);
  reorder([]);                                               // back to the configured order for the new run
  redraw();
  try {
    const res = await fetch('/api/race', { method: 'POST', headers: JSON_H, body: JSON.stringify({ text }) });
    if (!res.ok) throw new Error((await res.json()).error || res.status);
    const reader = res.body.getReader(), dec = new TextDecoder();
    let buf = '';
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const lines = buf.split('\n');
      buf = lines.pop();                                     // the tail is a partial line
      lines.filter(Boolean).map(JSON.parse).forEach(onEvent);
    }
  } catch (err) {
    $('#foot').textContent = `race failed: ${err.message}`;
  } finally {
    S.running = false; $('#go').disabled = false;
    setTimeout(() => prewarm(true), 800);
  }
}

/* ---------------------------------------------------------------- boot */
(async () => {
  build(await (await fetch('/api/config')).json());
  prewarm(true);
  $('#form').addEventListener('submit', go);
  $('#text').addEventListener('input', () => prewarm());
  $('#text').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('#form').requestSubmit(); }
  });
  $('#breakdown').addEventListener('change', (e) => {
    S.bars = e.target.checked;
    $('#legend').hidden = !S.bars;
    redraw();
  });
  window.addEventListener('resize', redraw);
})();
