const THREE = await import((window.__resources && window.__resources.three) || 'https://unpkg.com/three@0.160.0/build/three.module.js');

const SQ3 = Math.sqrt(3), COLS = 26, ROWS = 18, D2R = Math.PI / 180;
const OX = -SQ3 * (COLS - 0.5) / 2, OZ = -1.5 * (ROWS - 1) / 2;
const MINX = OX - SQ3 / 2, MAXX = -MINX, MINZ = OZ - 1, MAXZ = -MINZ, MW = MAXX - MINX, MD = MAXZ - MINZ;

function hash(x, y, s) { const h = Math.sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453; return h - Math.floor(h); }
function vnoise(x, y, s) {
  const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  const a = hash(xi, yi, s), b = hash(xi + 1, yi, s), c = hash(xi, yi + 1, s), d = hash(xi + 1, yi + 1, s);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
function fbm(x, y, s = 0, o = 5) { let t = 0, a = 0.5, f = 1, n = 0; for (let i = 0; i < o; i++) { t += a * vnoise(x * f, y * f, s + i * 13); n += a; a *= 0.5; f *= 2.03; } return t / n; }
function ridged(x, y, s) { let t = 0, a = 0.5, f = 1, n = 0; for (let i = 0; i < 4; i++) { t += a * (1 - Math.abs(vnoise(x * f, y * f, s + i * 7) * 2 - 1)); n += a; a *= 0.5; f *= 2.1; } return t / n; }
const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
let seed = 918273; const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };

export const TERRAIN = {
  plain: { name: 'Równina', cost: 1, def: 0 },
  field: { name: 'Pola uprawne', cost: 1, def: 5 },
  forest: { name: 'Las', cost: 2, def: 25 },
  hills: { name: 'Wzgórza', cost: 2, def: 30 },
  mountain: { name: 'Góry', cost: 3, def: 50 },
  urban: { name: 'Teren zabudowany', cost: 1, def: 40 },
  water: { name: 'Akwen', cost: Infinity, def: 0 },
};
const TYPES = {
  tank: { label: 'Czołg podstawowy', abbr: 'PANC', move: 5, hard: 8, soft: 6, def: 7, range: '1', vision: 3, ammoMax: 8, hpMax: 10, tags: ['Pancerna', 'Gąsienicowa', 'Ogień bezpośredni'], y: 0.62 },
  inf: { label: 'Piechota zmechanizowana', abbr: 'PIECH', move: 3, hard: 4, soft: 6, def: 5, range: '1', vision: 2, ammoMax: 10, hpMax: 10, tags: ['Piechota', 'Ppanc. ATGM', '+obrona w mieście'], y: 0.5 },
  mlrs: { label: 'Artyleria rakietowa', abbr: 'ART', move: 4, hard: 5, soft: 9, def: 2, range: '3–6', vision: 2, ammoMax: 2, hpMax: 6, tags: ['Wsparcie ogniowe', 'Kołowa', 'Ostrzał pośredni'], y: 0.78, note: 'Nie może strzelać po wykonaniu ruchu' },
};
const NAMES = { tank: ['KT-3 „Wilk”', 'BT-9 „Burza”'], inf: ['Pluton „Ryś”', 'Pluton „Sokół”'], mlrs: ['MR-6 „Szerszeń”', 'MR-12 „Żar”'] };
const RANKS = ['Rekruci', 'Regularni', 'Doświadczeni', 'Weterani'];
const FACTIONS = [
  { name: 'Sojusz Północny', short: 'SP', color: '#5b93d6', c3: 0x5b93d6, body: 0x4f5934, vest: 0x3d4529 },
  { name: 'Pakt Wschodni', short: 'PW', color: '#d76a52', c3: 0xd76a52, body: 0x7a7354, vest: 0x5d5840 },
];

// ---------- terrain ----------
function riverZ(x) { return OZ + 1.5 * (ROWS - 1) * 0.6 + Math.sin(x * 0.21 + 1) * 2.0 + (fbm(x * 0.08, 3.3, 41, 3) - 0.5) * 5; }
function terr(x, z, withRiver) {
  const u = (x - MINX) / MW, v = (z - MINZ) / MD;
  const n = fbm(x * 0.07 + 3, z * 0.07 + 7, 1);
  const land = smooth(0.07, 0.2, u + (n - 0.5) * 0.35);
  const hills = Math.max(0, fbm(x * 0.11 + 11, z * 0.11 - 4, 5) - 0.5) * 2.4;
  const mz = smooth(0.6, 0.92, u * 0.55 + (1 - v) * 0.6 + (fbm(x * 0.05, z * 0.05, 9) - 0.5) * 0.45);
  const mount = mz * (0.35 + ridged(x * 0.17, z * 0.17, 21)) * 2.1;
  let h = land * (0.2 + hills * 0.85 + mount) + (1 - land) * -0.75 + (fbm(x * 0.7, z * 0.7, 33, 3) - 0.5) * 0.07;
  const d = Math.abs(z - riverZ(x));
  const rm = smooth(0.95, 0.8, u) * (1 - mz) * land;
  if (withRiver) {
    const valley = smooth(2.5, 0.3, d) * rm;
    h -= valley * Math.max(0, h - 0.15) * 0.6;
    const carve = smooth(0.3, 0.06, d) * rm;
    h = h * (1 - carve) - 0.12 * carve;
  }
  return { h, d, rm };
}
const HEX = [];
function center(c, r) { return { x: OX + SQ3 * (c + 0.5 * (r & 1)), z: OZ + 1.5 * r }; }
function hexAt(x, z) {
  const px = x - OX, pz = z - OZ, q = SQ3 / 3 * px - pz / 3, r = 2 / 3 * pz, s = -q - r;
  let rx = Math.round(q), rz = Math.round(r), ry = Math.round(s);
  const dx = Math.abs(rx - q), dz = Math.abs(rz - r), dy = Math.abs(ry - s);
  if (dx > dy && dx > dz) rx = -ry - rz; else if (dy > dz) ry = -rx - rz; else rz = -rx - ry;
  const row = rz, col = rx + (row - (row & 1)) / 2;
  if (col < 0 || col >= COLS || row < 0 || row >= ROWS) return null;
  return HEX[row * COLS + col];
}
const NB = [[[1, 0], [0, -1], [-1, -1], [-1, 0], [-1, 1], [0, 1]], [[1, 0], [1, -1], [0, -1], [-1, 0], [0, 1], [1, 1]]];
function neighbors(h) { const out = []; for (const [dc, dr] of NB[h.r & 1]) { const c = h.c + dc, r = h.r + dr; if (c >= 0 && c < COLS && r >= 0 && r < ROWS) out.push(HEX[r * COLS + c]); } return out; }
function heightAt(x, z) {
  let h = terr(x, z, true).h;
  const hx = hexAt(x, z);
  if (hx && hx.type === 'urban') { const w = 0.92 * smooth(1.0, 0.5, Math.hypot(x - hx.x, z - hx.z)); h = h * (1 - w) + hx.hFlat * w; }
  return h;
}
const gy = (x, z) => Math.max(heightAt(x, z), 0);

function buildHexes() {
  for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) {
    const { x, z } = center(c, r);
    const t = terr(x, z, false), tr = terr(x, z, true);
    const h = t.h, moist = fbm(x * 0.13 + 50, z * 0.13 + 20, 77), farm = fbm(x * 0.2 - 30, z * 0.2, 88);
    let type;
    if (h < 0.02) type = 'water';
    else if (h > 1.45) type = 'mountain';
    else if (h > 0.7) type = moist > 0.66 ? 'forest' : 'hills';
    else if (moist > 0.61) type = 'forest';
    else if (farm > 0.5 && h > 0.12) type = 'field';
    else type = 'plain';
    HEX.push({ c, r, x, z, h: tr.h, type, river: type !== 'water' && t.rm > 0.3 && t.d < 0.8, road: false, city: null, unit: null });
  }
}
function nearest(u, v, pred) {
  const tx = MINX + u * MW, tz = MINZ + v * MD; let best = null, bd = 1e9;
  for (const h of HEX) { if (!pred(h)) continue; const d = Math.hypot(h.x - tx, h.z - tz); if (d < bd) { bd = d; best = h; } }
  return best;
}
const CITIES = [
  { name: 'Wierzbin', u: 0.38, v: 0.5, size: 4 },
  { name: 'Dębogród', u: 0.68, v: 0.42, size: 3 },
  { name: 'Port Mirów', u: 0.2, v: 0.8, size: 2 },
];
function buildCities() {
  const okLand = h => h.type !== 'water' && h.type !== 'mountain' && !h.river;
  for (const C of CITIES) {
    const ctr = nearest(C.u, C.v, h => okLand(h) && h.type !== 'hills' && !h.city);
    C.hex = ctr; const set = [ctr];
    for (const n of neighbors(ctr)) if (set.length <= C.size && okLand(n) && n.type !== 'hills') set.push(n);
    for (const h of set) { h.type = 'urban'; h.city = C.name; h.core = h === ctr; h.hFlat = Math.max(h.h, 0.1); }
  }
}
function roadPath(a, b) {
  const cost = h => h.type === 'water' ? 7 : h.type === 'mountain' ? 9 : h.type === 'hills' ? 3 : h.type === 'forest' ? 2 : h.road ? 0.6 : 1;
  const dist = new Map([[a, 0]]), prev = new Map(), open = [a], done = new Set();
  while (open.length) {
    open.sort((p, q) => dist.get(p) - dist.get(q)); const k = open.shift();
    if (k === b) break; done.add(k);
    for (const n of neighbors(k)) {
      if (done.has(n)) continue;
      const nd = dist.get(k) + cost(n) + (n.river ? 1.5 : 0);
      if (!dist.has(n) || nd < dist.get(n)) { dist.set(n, nd); prev.set(n, k); if (!open.includes(n)) open.push(n); }
    }
  }
  const p = [b]; let k = b; while (prev.has(k)) { k = prev.get(k); p.unshift(k); } return p;
}

// ---------- geometry helpers ----------
function patchGeo(cx, cz, scale, lift) {
  const pos = [], idx = [], n = 4;
  for (let s = 0; s < 6; s++) {
    const a0 = (60 * s - 30) * D2R, a1 = (60 * (s + 1) - 30) * D2R;
    const Bx = cx + scale * Math.cos(a0), Bz = cz + scale * Math.sin(a0), Cx = cx + scale * Math.cos(a1), Cz = cz + scale * Math.sin(a1);
    const map = {};
    for (let i = 0; i <= n; i++) for (let j = 0; j <= n - i; j++) {
      const x = cx + (Bx - cx) * i / n + (Cx - cx) * j / n, z = cz + (Bz - cz) * i / n + (Cz - cz) * j / n;
      map[i + ',' + j] = pos.length / 3; pos.push(x, gy(x, z) + lift, z);
    }
    for (let i = 0; i < n; i++) for (let j = 0; j < n - i; j++) {
      idx.push(map[i + ',' + j], map[(i + 1) + ',' + j], map[i + ',' + (j + 1)]);
      if (j < n - i - 1) idx.push(map[(i + 1) + ',' + j], map[(i + 1) + ',' + (j + 1)], map[i + ',' + (j + 1)]);
    }
  }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); return g;
}
function ringGeo(cx, cz, r0, r1, lift) {
  const pos = [], idx = [], seg = 5;
  for (let s = 0; s < 6; s++) for (let k = 0; k < seg; k++) {
    const t = k / seg, a0 = (60 * s - 30) * D2R, a1 = (60 * (s + 1) - 30) * D2R;
    const px = Math.cos(a0) * (1 - t) + Math.cos(a1) * t, pz = Math.sin(a0) * (1 - t) + Math.sin(a1) * t;
    for (const rr of [r0, r1]) { const x = cx + px * rr, z = cz + pz * rr; pos.push(x, gy(x, z) + lift, z); }
  }
  const N = 6 * seg;
  for (let i = 0; i < N; i++) { const a = i * 2, b = a + 1, c = ((i + 1) % N) * 2, d = c + 1; idx.push(a, c, b, b, c, d); }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); return g;
}
const overlayMat = (color, opacity) => new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4, toneMapped: false });

// ---------- unit models ----------
const mat = (c, r = 0.75, m = 0.15) => new THREE.MeshStandardMaterial({ color: c, roughness: r, metalness: m });
function add(geo, m, x, y, z, parent, rx = 0, rz = 0, ry = 0) {
  const o = new THREE.Mesh(geo, m); o.position.set(x, y, z); o.rotation.set(rx, ry, rz); o.castShadow = true; o.receiveShadow = true; parent.add(o); return o;
}
const box = (w, h, d, m, x, y, z, p) => add(new THREE.BoxGeometry(w, h, d), m, x, y, z, p);
const cyl = (rt, rb, h, seg, m, x, y, z, p, rx = 0, rz = 0) => add(new THREE.CylinderGeometry(rt, rb, h, seg), m, x, y, z, p, rx, rz);

function makeTank(F) {
  const g = new THREE.Group(), body = mat(F.body, 0.8, 0.15), dark = mat(0x22231f, 0.95, 0.05), metal = mat(0x3c3e38, 0.55, 0.45), acc = mat(F.c3, 0.5, 0.1);
  for (const s of [-1, 1]) {
    box(0.74, 0.1, 0.1, dark, 0, 0.06, s * 0.17, g);
    for (let i = 0; i < 6; i++) cyl(0.045, 0.045, 0.03, 12, metal, -0.27 + i * 0.108, 0.055, s * 0.2, g, Math.PI / 2);
    box(0.62, 0.065, 0.012, body, 0, 0.135, s * 0.226, g);
  }
  box(0.7, 0.09, 0.36, body, 0, 0.13, 0, g);
  box(0.64, 0.05, 0.46, body, -0.02, 0.195, 0, g);
  box(0.16, 0.02, 0.44, body, 0.33, 0.17, 0, g).rotation.z = -0.55;
  box(0.13, 0.012, 0.3, dark, -0.27, 0.225, 0, g);
  const shape = new THREE.Shape();
  [[-0.2, -0.15], [0.08, -0.165], [0.2, -0.07], [0.2, 0.07], [0.08, 0.165], [-0.2, 0.15], [-0.25, 0.1], [-0.25, -0.1]].forEach(([x, y], i) => i ? shape.lineTo(x, y) : shape.moveTo(x, y));
  const tg = new THREE.ExtrudeGeometry(shape, { depth: 0.085, bevelEnabled: true, bevelThickness: 0.012, bevelSize: 0.012, bevelSegments: 1 });
  tg.rotateX(-Math.PI / 2);
  const tur = new THREE.Group(); tur.position.set(-0.03, 0.225, 0); g.add(tur);
  add(tg, body, 0, 0, 0, tur);
  box(0.07, 0.07, 0.1, body, 0.22, 0.045, 0, tur);
  cyl(0.017, 0.019, 0.52, 10, metal, 0.5, 0.05, 0, tur, 0, Math.PI / 2);
  cyl(0.026, 0.026, 0.07, 10, metal, 0.42, 0.05, 0, tur, 0, Math.PI / 2);
  cyl(0.022, 0.022, 0.03, 10, dark, 0.76, 0.05, 0, tur, 0, Math.PI / 2);
  cyl(0.04, 0.046, 0.035, 12, body, -0.07, 0.115, 0.07, tur);
  box(0.07, 0.012, 0.012, dark, -0.03, 0.142, 0.07, tur);
  cyl(0.032, 0.036, 0.025, 10, body, -0.05, 0.11, -0.07, tur);
  cyl(0.004, 0.004, 0.34, 4, dark, -0.2, 0.26, -0.11, tur);
  for (const s of [-1, 1]) { box(0.06, 0.04, 0.005, acc, -0.02, 0.05, s * 0.172, tur); for (let i = 0; i < 3; i++) cyl(0.012, 0.012, 0.04, 6, dark, 0.06 - i * 0.025, 0.08, s * 0.15, tur, 0.4 * s); }
  return g;
}
function soldier(F, kneel, gun) {
  const s = new THREE.Group(), uni = mat(F.body, 0.9, 0), vest = mat(F.vest, 0.9, 0), skin = mat(0xb98d6c, 0.8, 0), dark = mat(0x1f201c, 0.7, 0.3);
  const lh = kneel ? 0.05 : 0.085;
  box(0.024, lh, 0.026, uni, kneel ? 0.02 : 0, lh / 2, -0.017, s); box(0.024, lh, 0.026, uni, kneel ? -0.015 : 0, lh / 2, 0.017, s);
  box(0.045, 0.078, 0.064, vest, 0, lh + 0.04, 0, s);
  box(0.032, 0.055, 0.05, uni, -0.038, lh + 0.05, 0, s);
  add(new THREE.SphereGeometry(0.02, 10, 8), skin, 0.004, lh + 0.1, 0, s);
  add(new THREE.SphereGeometry(0.027, 12, 6, 0, Math.PI * 2, 0, Math.PI / 2), uni, 0, lh + 0.102, 0, s);
  box(0.06, 0.016, 0.016, uni, 0.03, lh + 0.06, 0.03, s); box(0.06, 0.016, 0.016, uni, 0.035, lh + 0.06, -0.025, s);
  const rf = box(gun ? 0.15 : 0.12, gun ? 0.022 : 0.012, gun ? 0.022 : 0.012, dark, 0.06, lh + 0.07, 0.01, s); rf.rotation.z = 0.12;
  return s;
}
function makeInf(F) {
  const g = new THREE.Group();
  [[0.13, 0, false], [-0.02, 0.15, true], [-0.03, -0.15, false], [-0.18, 0.06, false], [-0.15, -0.12, true]].forEach(([x, z, k], i) => {
    const s = soldier(F, k, i === 1); s.scale.setScalar(1.5); s.position.set(x, 0, z); s.rotation.y = (hash(i, 3, 1) - 0.5) * 0.6; g.add(s);
  });
  return g;
}
function makeMLRS(F) {
  const g = new THREE.Group(), body = mat(F.body, 0.8, 0.15), dark = mat(0x22231f, 0.95, 0.05), tire = mat(0x1a1a18, 0.95, 0), metal = mat(0x45473f, 0.5, 0.5), glass = mat(0x1b2a33, 0.15, 0.7), acc = mat(F.c3, 0.5, 0.1);
  box(0.78, 0.04, 0.2, dark, 0, 0.11, 0, g);
  for (const x of [0.26, -0.06, -0.23]) for (const s of [-1, 1]) {
    cyl(0.062, 0.062, 0.05, 16, tire, x, 0.062, s * 0.13, g, Math.PI / 2);
    cyl(0.032, 0.032, 0.052, 8, metal, x, 0.062, s * 0.13, g, Math.PI / 2);
  }
  box(0.2, 0.15, 0.3, body, 0.28, 0.205, 0, g);
  box(0.01, 0.065, 0.26, glass, 0.381, 0.235, 0, g);
  for (const s of [-1, 1]) { box(0.08, 0.05, 0.005, glass, 0.3, 0.24, s * 0.151, g); box(0.05, 0.03, 0.004, acc, 0.3, 0.18, s * 0.152, g); box(0.13, 0.012, 0.08, body, 0.27, 0.13, s * 0.14, g); box(0.38, 0.012, 0.08, body, -0.14, 0.13, s * 0.14, g); }
  box(0.18, 0.015, 0.28, body, 0.27, 0.287, 0, g);
  box(0.48, 0.05, 0.3, body, -0.13, 0.155, 0, g);
  const pv = new THREE.Group(); pv.position.set(-0.34, 0.19, 0); pv.rotation.z = 0.32; g.add(pv);
  box(0.48, 0.15, 0.26, body, 0.24, 0.085, 0, pv);
  box(0.47, 0.012, 0.27, dark, 0.24, 0.165, 0, pv);
  for (let row = 0; row < 2; row++) for (let col = 0; col < 3; col++) cyl(0.03, 0.03, 0.012, 12, dark, 0.482, 0.05 + row * 0.07, (col - 1) * 0.08, pv, 0, Math.PI / 2);
  cyl(0.012, 0.012, 0.16, 6, metal, -0.06, 0.22, 0.08, g, 0, 1.2);
  return g;
}
const BUILD = { tank: makeTank, inf: makeInf, mlrs: makeMLRS };

function makePortraits() {
  const W = 640, H = 340, r = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
  r.setSize(W, H, false); r.outputColorSpace = THREE.SRGBColorSpace; r.toneMapping = THREE.ACESFilmicToneMapping; r.shadowMap.enabled = true; r.shadowMap.type = THREE.PCFSoftShadowMap;
  const sc = new THREE.Scene(); sc.background = new THREE.Color(0x3a3f35); sc.fog = new THREE.Fog(0x3a3f35, 2.2, 6);
  sc.add(new THREE.HemisphereLight(0xdfe6ea, 0x3a3628, 1.2));
  const dl = new THREE.DirectionalLight(0xfff0d8, 3.2); dl.position.set(1.2, 2.4, 1.6); dl.castShadow = true; dl.shadow.mapSize.set(1024, 1024);
  Object.assign(dl.shadow.camera, { left: -1, right: 1, top: 1, bottom: -1, near: 0.1, far: 6 }); dl.shadow.bias = -0.0005; sc.add(dl);
  const ground = new THREE.Mesh(new THREE.CircleGeometry(5, 48), new THREE.MeshStandardMaterial({ color: 0x6b7150, roughness: 1 })); ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true; sc.add(ground);
  const cam = new THREE.PerspectiveCamera(24, W / H, 0.05, 20), out = {};
  for (const t of ['tank', 'inf', 'mlrs']) for (let f = 0; f < 2; f++) {
    const m = BUILD[t](FACTIONS[f]); m.rotation.y = -0.6; sc.add(m);
    const bb = new THREE.Box3().setFromObject(m), size = bb.getSize(new THREE.Vector3()).length(), c = bb.getCenter(new THREE.Vector3());
    cam.position.set(c.x + size * 0.82, c.y + size * 0.4, c.z + size * 1.02); cam.lookAt(c.x, c.y - 0.02, c.z);
    r.render(sc, cam); out[t + f] = r.domElement.toDataURL('image/jpeg', 0.9); sc.remove(m);
  }
  r.dispose(); r.forceContextLoss(); return out;
}

// ---------- game ----------
export function createGame(container, labels, cb) {
  seed = 918273; HEX.length = 0;
  buildHexes(); buildCities();
  const C = CITIES.map(c => c.hex);
  const edgeE = nearest(0.99, 0.62, h => h.type !== 'water' && h.type !== 'mountain');
  const edgeS = nearest(0.42, 0.99, h => h.type !== 'water' && h.type !== 'mountain');
  const roads = [roadPath(C[2], C[0]), roadPath(C[0], C[1]), roadPath(C[1], edgeE), roadPath(C[0], edgeS)];
  roads.forEach(p => p.forEach(h => { if (h.type !== 'water') h.road = true; }));

  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace; renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.05;
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  container.appendChild(renderer.domElement); Object.assign(renderer.domElement.style, { display: 'block', width: '100%', height: '100%', touchAction: 'none' });
  const scene = new THREE.Scene(); const SKY = 0xa9b4b2;
  scene.background = new THREE.Color(SKY); scene.fog = new THREE.Fog(SKY, 38, 90);
  const camera = new THREE.PerspectiveCamera(34, 1, 0.1, 220);
  scene.add(new THREE.HemisphereLight(0xdde7ee, 0x4b4534, 1.0));
  const sun = new THREE.DirectionalLight(0xfff0d8, 2.7); sun.position.set(-18, 26, 14); sun.castShadow = true;
  sun.shadow.mapSize.set(4096, 4096); Object.assign(sun.shadow.camera, { left: -32, right: 32, top: 24, bottom: -24, near: 1, far: 90 });
  sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.03; scene.add(sun);

  // terrain mesh
  const EXT = 9, gw = MW + EXT * 2, gd = MD + EXT * 2;
  const geo = new THREE.PlaneGeometry(gw, gd, Math.round(gw * 6), Math.round(gd * 6)); geo.rotateX(-Math.PI / 2);
  const P = geo.attributes.position;
  for (let i = 0; i < P.count; i++) P.setY(i, heightAt(P.getX(i), P.getZ(i)));
  geo.computeVertexNormals();
  const N = geo.attributes.normal, cols = new Float32Array(P.count * 3);
  const K = h => new THREE.Color(h);
  const COL = { deep: K(0x17323b), shoal: K(0x5d8778), sand: K(0xc6b78a), g1: K(0x627c33), g2: K(0x87974b), forest: K(0x2f4a26), forest2: K(0x3f5a2d), hill: K(0x837b50), rock: K(0x756e5e), rock2: K(0xa29c8f), snow: K(0xeef0ef), urban: K(0x86837b), fA: K(0xbaa65a), fB: K(0x7a9640), fC: K(0x9d8253), fD: K(0x9ba25e) };
  const c = new THREE.Color(), tmp = new THREE.Color();
  for (let i = 0; i < P.count; i++) {
    const x = P.getX(i), y = P.getY(i), z = P.getZ(i), ny = N.getY(i), k = fbm(x * 0.35, z * 0.35, 61, 3);
    const hu = hexAt(x, z);
    if (y < 0.03) { c.copy(COL.deep).lerp(COL.shoal, smooth(-0.7, -0.05, y)).lerp(COL.sand, smooth(-0.06, 0.03, y)); }
    else {
      c.copy(COL.g1).lerp(COL.g2, smooth(0.35, 0.7, k));
      const jx = x + (fbm(x * 0.8, z * 0.8, 71, 2) - 0.5) * 0.55, jz = z + (fbm(x * 0.8 + 9, z * 0.8, 72, 2) - 0.5) * 0.55, hj = hexAt(jx, jz);
      if (hu && hu.type === 'urban') c.lerp(COL.urban, 0.85 * smooth(1.0, 0.7, Math.hypot(x - hu.x, z - hu.z)));
      else if (hu && hu.type === 'field') {
        const a = hash(hu.c, hu.r, 5) * Math.PI, ca = Math.cos(a), sa = Math.sin(a);
        const side = ((x - hu.x) * -sa + (z - hu.z) * ca) > (hash(hu.c, hu.r, 8) - 0.5) * 0.8 ? 0 : 1;
        const pal = [[COL.fA, COL.fD], [COL.fB, COL.fC]][(side + (hash(hu.c, hu.r, 9) > 0.5 ? 1 : 0)) % 2];
        const st = Math.sin((x * ca + z * sa) * 24) * 0.5 + 0.5;
        tmp.copy(pal[0]).lerp(pal[1], st * 0.35); c.lerp(tmp, 0.8 * smooth(0.98, 0.8, Math.hypot(x - hu.x, z - hu.z)));
      }
      if (hj && hj.type === 'forest') { tmp.copy(COL.forest).lerp(COL.forest2, k); c.lerp(tmp, 0.85); }
      c.lerp(COL.sand, smooth(0.16, 0.04, y));
      c.lerp(COL.hill, smooth(0.6, 1.1, y) * 0.6);
      tmp.copy(COL.rock).lerp(COL.rock2, k); c.lerp(tmp, Math.min(1, smooth(0.18, 0.42, 1 - ny) + smooth(1.3, 1.8, y) * 0.85));
      c.lerp(COL.snow, smooth(1.85, 2.15, y + (k - 0.5) * 0.35) * smooth(0.55, 0.8, ny));
    }
    c.multiplyScalar(0.88 + k * 0.24);
    if (!hu) c.multiplyScalar(0.6);
    cols[i * 3] = c.r; cols[i * 3 + 1] = c.g; cols[i * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(cols, 3));
  const terrain = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.95, metalness: 0 }));
  terrain.receiveShadow = true; terrain.castShadow = true; scene.add(terrain);

  const water = new THREE.Mesh(new THREE.PlaneGeometry(gw + 80, gd + 80), new THREE.MeshStandardMaterial({ color: 0x2c5866, roughness: 0.12, metalness: 0.25, transparent: true, opacity: 0.84 }));
  water.rotation.x = -Math.PI / 2; water.receiveShadow = true; scene.add(water);

  // hex grid lines
  const lp = [];
  for (const h of HEX) for (let s = 0; s < 6; s++) {
    const a0 = (60 * s - 30) * D2R, a1 = (60 * (s + 1) - 30) * D2R;
    for (let k = 0; k < 5; k++) for (const t of [k / 5, (k + 1) / 5]) {
      const x = h.x + Math.cos(a0) * (1 - t) + Math.cos(a1) * t, z = h.z + Math.sin(a0) * (1 - t) + Math.sin(a1) * t;
      lp.push(x, gy(x, z) + 0.025, z);
    }
  }
  const lg = new THREE.BufferGeometry(); lg.setAttribute('position', new THREE.Float32BufferAttribute(lp, 3));
  scene.add(new THREE.LineSegments(lg, new THREE.LineBasicMaterial({ color: 0x0d120c, transparent: true, opacity: 0.2, depthWrite: false })));

  // roads
  const roadPts = new Map();
  const roadMat = new THREE.MeshStandardMaterial({ color: 0x4d4a42, roughness: 1, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
  for (const p of roads) {
    if (p.length < 2) continue;
    const curve = new THREE.CatmullRomCurve3(p.map(h => new THREE.Vector3(h.x, 0, h.z)));
    const pts = curve.getSpacedPoints(p.length * 14), pos = [], idx = [];
    pts.forEach((pt, i) => {
      const nx = pts[Math.min(i + 1, pts.length - 1)], pr = pts[Math.max(i - 1, 0)];
      let dx = nx.x - pr.x, dz = nx.z - pr.z; const l = Math.hypot(dx, dz) || 1; dx /= l; dz /= l;
      for (const s of [-1, 1]) { const x = pt.x - dz * 0.065 * s, z = pt.z + dx * 0.065 * s, hh = heightAt(x, z); pos.push(x, hh < 0.02 ? 0.08 : hh + 0.02, z); }
      const hx = hexAt(pt.x, pt.z); if (hx) { if (!roadPts.has(hx)) roadPts.set(hx, []); roadPts.get(hx).push(pt); }
      if (i) { const b = (i - 1) * 2; idx.push(b, b + 2, b + 1, b + 1, b + 2, b + 3); }
    });
    const rg = new THREE.BufferGeometry(); rg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); rg.setIndex(idx); rg.computeVertexNormals();
    const rm = new THREE.Mesh(rg, roadMat); rm.receiveShadow = true; scene.add(rm);
  }
  const nearRoad = (h, x, z, d) => (roadPts.get(h) || []).some(p => Math.hypot(p.x - x, p.z - z) < d);

  // scatter: trees, buildings, rocks
  const dummy = new THREE.Object3D(), trees = [], blds = [], rocks = [];
  const inHex = (h, rad) => { for (;;) { const x = (rnd() * 2 - 1) * rad, z = (rnd() * 2 - 1) * rad; if (Math.hypot(x, z) < rad) return [h.x + x, h.z + z]; } };
  for (const h of HEX) {
    if (h.type === 'forest' || h.type === 'plain' || h.type === 'field') {
      const n = h.type === 'forest' ? 30 : h.type === 'plain' ? (rnd() < 0.5 ? 4 : 0) : 0;
      for (let i = 0; i < n; i++) {
        const [x, z] = inHex(h, 0.95), y = heightAt(x, z);
        if (y < 0.05 || nearRoad(h, x, z, 0.14)) continue;
        trees.push({ x, y, z, s: 0.7 + rnd() * 0.6, con: y > 0.6 ? rnd() < 0.8 : rnd() < 0.35, k: rnd() });
      }
    }
    if (h.type === 'urban') {
      const ang = hash(h.c, h.r, 3) * Math.PI, placed = [];
      for (let i = 0; i < 80 && placed.length < (h.core ? 22 : 14); i++) {
        const [x, z] = inHex(h, 0.86), w = 0.09 + rnd() * 0.12, d = 0.09 + rnd() * 0.12;
        if (nearRoad(h, x, z, 0.1 + Math.max(w, d) / 2)) continue;
        if (placed.some(p => Math.hypot(p[0] - x, p[1] - z) < (Math.max(w, d) + p[2]) * 0.62)) continue;
        placed.push([x, z, Math.max(w, d)]);
        const ctr = 1 - Math.hypot(x - h.x, z - h.z);
        const ht = h.core ? 0.08 + rnd() * 0.18 + ctr * rnd() * 0.45 : 0.06 + rnd() * 0.14;
        blds.push({ x, z, y: heightAt(x, z) - 0.03, w, d, ht: ht + 0.03, a: ang + (rnd() < 0.2 ? Math.PI / 4 : 0), k: rnd() });
      }
    }
    if (h.type === 'mountain' || h.type === 'hills') {
      for (let i = 0; i < (h.type === 'mountain' ? 8 : 3); i++) { const [x, z] = inHex(h, 0.9); rocks.push({ x, z, y: heightAt(x, z), s: 0.5 + rnd() * 1.2 }); }
    }
  }
  const conGeo = new THREE.ConeGeometry(0.075, 0.3, 7); conGeo.translate(0, 0.19, 0);
  const decGeo = new THREE.IcosahedronGeometry(0.085, 1); decGeo.translate(0, 0.14, 0);
  const trunkGeo = new THREE.CylinderGeometry(0.01, 0.014, 0.1, 5); trunkGeo.translate(0, 0.05, 0);
  const cons = trees.filter(t => t.con), decs = trees.filter(t => !t.con);
  const mkInst = (g, m, list, fn) => { const im = new THREE.InstancedMesh(g, m, Math.max(1, list.length)); im.count = list.length; list.forEach((t, i) => { fn(t, i, im); im.setMatrixAt(i, dummy.matrix); }); im.castShadow = true; im.receiveShadow = true; scene.add(im); return im; };
  const treeM = (t) => { dummy.position.set(t.x, t.y - 0.02, t.z); dummy.rotation.set(0, t.k * 6, 0); dummy.scale.set(t.s, t.s * (0.9 + t.k * 0.3), t.s); dummy.updateMatrix(); };
  const tc = new THREE.Color();
  mkInst(conGeo, mat(0xffffff, 0.9, 0), cons, (t, i, im) => { treeM(t); im.setColorAt(i, tc.setHex(0x2c4626).lerp(K(0x3d5a30), t.k)); });
  mkInst(decGeo, mat(0xffffff, 0.9, 0), decs, (t, i, im) => { treeM(t); im.setColorAt(i, tc.setHex(0x41602c).lerp(K(0x6b7f36), t.k)); });
  mkInst(trunkGeo, mat(0x4a3b2a, 1, 0), trees, (t) => treeM(t));
  const bGeo = new THREE.BoxGeometry(1, 1, 1); bGeo.translate(0, 0.5, 0);
  const bCols = [0xbab3a4, 0xa8a094, 0x8e8a80, 0xc6baa2, 0x9a7a64, 0x7d8386, 0xd0c8b6];
  mkInst(bGeo, mat(0xffffff, 0.85, 0.05), blds, (b, i, im) => { dummy.position.set(b.x, b.y, b.z); dummy.rotation.set(0, b.a, 0); dummy.scale.set(b.w, b.ht, b.d); dummy.updateMatrix(); im.setColorAt(i, tc.setHex(bCols[Math.floor(b.k * bCols.length)])); });
  mkInst(new THREE.DodecahedronGeometry(0.05, 0), mat(0x7d776a, 0.95, 0), rocks, (r) => { dummy.position.set(r.x, r.y, r.z); dummy.rotation.set(r.s, r.s * 3, 0); dummy.scale.set(r.s, r.s * 0.7, r.s); dummy.updateMatrix(); });

  // labels
  const mkLabel = (html) => { const d = document.createElement('div'); d.style.cssText = 'position:absolute;left:0;top:0;will-change:transform;pointer-events:none'; d.innerHTML = html; labels.appendChild(d); return d; };
  const cityLabels = CITIES.map(ci => ({ el: mkLabel(`<div style="transform:translate(-50%,-50%);font:600 12px 'IBM Plex Sans Condensed',sans-serif;letter-spacing:.16em;text-transform:uppercase;color:#f3f0e6;text-shadow:0 1px 2px rgba(0,0,0,.9),0 0 8px rgba(0,0,0,.6);white-space:nowrap">${ci.name}</div>`), p: new THREE.Vector3(ci.hex.x, gy(ci.hex.x, ci.hex.z + 0.8) + 0.15, ci.hex.z + 0.8) }));

  // units
  const SPAWN = [
    [0, 'tank', 0.32, 0.4, '1. Batalion Czołgów · 1. kompania', 2, 10, 8], [0, 'tank', 0.3, 0.56, '1. Batalion Czołgów · 2. kompania', 1, 8, 5],
    [0, 'inf', 0.38, 0.5, '3. Batalion Zmech. · 1. pluton', 1, 9, 7], [0, 'inf', 0.27, 0.7, '3. Batalion Zmech. · 2. pluton', 0, 10, 10],
    [0, 'mlrs', 0.21, 0.48, '11. Dywizjon Art. Rakietowej', 1, 6, 2],
    [1, 'tank', 0.63, 0.44, '4. Pułk Pancerny · 1. kompania', 1, 10, 7], [1, 'tank', 0.61, 0.6, '4. Pułk Pancerny · 3. kompania', 2, 7, 4],
    [1, 'inf', 0.68, 0.38, '9. Pułk Strzelców · 2. pluton', 1, 10, 9], [1, 'inf', 0.57, 0.74, '9. Pułk Strzelców · 4. pluton', 0, 8, 6],
    [1, 'mlrs', 0.76, 0.55, '2. Brygada Rakietowa · 1. bateria', 3, 5, 1],
  ];
  const units = [], unitRoots = [];
  const markerFill = (u) => u.fill.material.opacity = u.sel ? 0.32 : (u.hov ? 0.2 : 0.1);
  function placeMarker(u) {
    const h = HEX[u.r * COLS + u.c];
    u.ring.geometry.dispose(); u.ring.geometry = ringGeo(h.x, h.z, 0.6, u.sel ? 0.8 : 0.72, 0.035);
    u.fill.geometry.dispose(); u.fill.geometry = patchGeo(h.x, h.z, 0.6, 0.03);
    u.ring.material.opacity = u.moved && !u.sel ? 0.45 : 0.95; markerFill(u);
  }
  SPAWN.forEach(([f, type, uu, vv, des, xp, hp, ammo], id) => {
    const h = nearest(uu, vv, x => x.type !== 'water' && x.type !== 'mountain' && !x.unit);
    const F = FACTIONS[f], T = TYPES[type];
    const root = new THREE.Group(), model = BUILD[type](F); model.scale.setScalar(1.3); root.add(model);
    root.position.set(h.x, gy(h.x, h.z), h.z); root.rotation.y = f === 0 ? 0 : Math.PI;
    const u = { id, f, type, c: h.c, r: h.r, hp, xp, ammo, des, moved: false, root, sel: false, hov: false };
    root.traverse(o => o.userData.unit = u);
    u.ring = new THREE.Mesh(new THREE.BufferGeometry(), overlayMat(F.c3, 0.95)); u.fill = new THREE.Mesh(new THREE.BufferGeometry(), overlayMat(F.c3, 0.1));
    scene.add(root, u.ring, u.fill); h.unit = u; units.push(u); unitRoots.push(root);
    const pct = Math.round(hp / T.hpMax * 100);
    u.label = mkLabel(`<div style="transform:translate(-50%,-100%);display:flex;align-items:center;gap:5px;padding:2px 5px 2px 2px;background:rgba(14,16,13,.82);border:1px solid rgba(255,255,255,.14);font:600 9px 'IBM Plex Mono',monospace;color:#ebe8df;letter-spacing:.06em;white-space:nowrap;transition:opacity .2s"><span style="width:4px;height:15px;background:${F.color}"></span><span>${T.abbr}</span><span style="width:26px;height:4px;background:rgba(255,255,255,.15)"><span style="display:block;height:100%;width:${pct}%;background:${pct > 60 ? '#b9d38a' : pct > 35 ? '#e2c069' : '#e07c5e'}"></span></span></div>`);
    u.lp = new THREE.Vector3();
    placeMarker(u);
  });

  // overlays
  const overlay = new THREE.Group(); scene.add(overlay);
  const hoverRing = new THREE.Mesh(new THREE.BufferGeometry(), overlayMat(0xffffff, 0.85)), hoverFill = new THREE.Mesh(new THREE.BufferGeometry(), overlayMat(0xffffff, 0.1));
  scene.add(hoverRing, hoverFill);
  const dotGeo = new THREE.SphereGeometry(0.05, 10, 8), dots = new THREE.InstancedMesh(dotGeo, new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false }), 80); dots.count = 0; scene.add(dots);

  const game = { turn: 1, active: 0, sel: null, reach: null };
  const moveCost = (u, h) => {
    if (h.type === 'water') return Infinity;
    if (h.type === 'mountain' && u.type === 'mlrs') return Infinity;
    let c = h.road ? 1 : TERRAIN[h.type].cost;
    if (u.type === 'mlrs' && h.type === 'forest' && !h.road) c = 3;
    if (h.river && !h.road) c += 1;
    return c;
  };
  function reachOf(u) {
    const start = HEX[u.r * COLS + u.c], dist = new Map([[start, 0]]), prev = new Map(), open = [start], mp = TYPES[u.type].move;
    while (open.length) {
      open.sort((a, b) => dist.get(a) - dist.get(b)); const k = open.shift();
      for (const n of neighbors(k)) {
        if (n.unit) continue;
        const nd = dist.get(k) + moveCost(u, n); if (nd > mp) continue;
        if (!dist.has(n) || nd < dist.get(n)) { dist.set(n, nd); prev.set(n, k); if (!open.includes(n)) open.push(n); }
      }
    }
    dist.delete(start); return { dist, prev, start };
  }
  function clearOverlay() { overlay.children.slice().forEach(m => { m.geometry.dispose(); overlay.remove(m); }); dots.count = 0; }
  function select(u) {
    if (game.sel) { game.sel.sel = false; placeMarker(game.sel); }
    clearOverlay(); game.sel = u; game.reach = null;
    if (!u) return;
    u.sel = true; placeMarker(u);
    game.reach = reachOf(u);
    const col = FACTIONS[u.f].c3, fm = overlayMat(col, 0.2), rm = overlayMat(col, 0.55);
    for (const h of game.reach.dist.keys()) { overlay.add(new THREE.Mesh(patchGeo(h.x, h.z, 0.9, 0.03), fm)); overlay.add(new THREE.Mesh(ringGeo(h.x, h.z, 0.86, 0.92, 0.035), rm)); }
  }
  function pathTo(h) { const p = [h]; let k = h; while (game.reach.prev.has(k)) { k = game.reach.prev.get(k); p.unshift(k); } return p; }
  function showPath(h) {
    dots.count = 0; if (!game.sel || !game.reach || !game.reach.dist.has(h)) return;
    const p = pathTo(h); const curve = new THREE.CatmullRomCurve3(p.map(x => new THREE.Vector3(x.x, 0, x.z)));
    const n = Math.min(80, (p.length - 1) * 5); const pts = curve.getSpacedPoints(n);
    pts.slice(2).forEach((pt, i) => { dummy.position.set(pt.x, gy(pt.x, pt.z) + 0.1, pt.z); dummy.rotation.set(0, 0, 0); dummy.scale.setScalar(i === pts.length - 3 ? 1.8 : 1); dummy.updateMatrix(); dots.setMatrixAt(i, dummy.matrix); });
    dots.count = Math.max(0, pts.length - 2); dots.instanceMatrix.needsUpdate = true;
  }
  function moveUnit(u, target) {
    const p = pathTo(target); HEX[u.r * COLS + u.c].unit = null; target.unit = u;
    u.c = target.c; u.r = target.r; u.moved = true;
    u.anim = { path: p.map(h => new THREE.Vector3(h.x, gy(h.x, h.z), h.z)), i: 0, t: 0 };
    u.ring.visible = u.fill.visible = false;
    select(null); emitState();
  }
  function emitState() {
    cb.onState && cb.onState({
      turn: game.turn, active: game.active,
      factions: FACTIONS.map((F, i) => { const us = units.filter(u => u.f === i); return { name: F.name, short: F.short, color: F.color, units: us.length, ready: us.filter(u => !u.moved).length }; }),
    });
  }
  function unitInfo(u, portraits) {
    const T = TYPES[u.type], F = FACTIONS[u.f], segs = [];
    for (let i = 0; i < T.hpMax; i++) segs.push({ c: i < u.hp ? (u.hp / T.hpMax > 0.6 ? '#b9d38a' : u.hp / T.hpMax > 0.35 ? '#e2c069' : '#e07c5e') : 'rgba(233,231,223,0.12)' });
    const bar = (v, m) => Math.round(Math.min(1, v / m) * 100) + '%';
    const h = HEX[u.r * COLS + u.c];
    return {
      name: NAMES[u.type][u.f], typeLabel: T.label, des: u.des, color: F.color, faction: F.name, portrait: portraits[u.type + u.f] || '',
      hp: u.hp, hpMax: T.hpMax, segs,
      stats: [
        { label: 'Atak · pancerne', value: T.hard, w: bar(T.hard, 10) }, { label: 'Atak · piechota', value: T.soft, w: bar(T.soft, 10) },
        { label: 'Obrona', value: T.def, w: bar(T.def, 10) }, { label: 'Punkty ruchu', value: T.move, w: bar(T.move, 6) },
        { label: 'Zasięg (heks)', value: T.range, w: bar(u.type === 'mlrs' ? 6 : 1, 6) }, { label: 'Widzenie', value: T.vision, w: bar(T.vision, 4) },
        { label: 'Amunicja', value: u.ammo + '/' + T.ammoMax, w: bar(u.ammo, T.ammoMax) }, { label: 'Teren · obrona', value: '+' + TERRAIN[h.type].def + '%', w: bar(TERRAIN[h.type].def, 50) },
      ],
      tags: T.tags, rank: RANKS[u.xp], rankPips: [0, 1, 2].map(i => ({ c: i < u.xp ? '#e2c069' : 'rgba(233,231,223,0.18)' })),
      own: u.f === game.active,
      status: u.f !== game.active ? 'Jednostka przeciwnika' : u.moved ? 'Wykonała ruch w tej turze' : 'Gotowa do działania',
      statusColor: u.f !== game.active ? F.color : u.moved ? '#a19f95' : '#b9d38a',
      note: T.note || '',
    };
  }

  // camera
  const cam = { tx: 0, tz: 1, d: 24, yaw: 0 };
  const keys = new Set();
  function updateCamera() {
    cam.tx = Math.max(MINX + 2, Math.min(MAXX - 2, cam.tx)); cam.tz = Math.max(MINZ + 2, Math.min(MAXZ - 2, cam.tz));
    const p = 0.82 + (cam.d - 8) / 37 * 0.3, ty = 0.4;
    camera.position.set(cam.tx + Math.sin(cam.yaw) * Math.cos(p) * cam.d, ty + Math.sin(p) * cam.d, cam.tz + Math.cos(cam.yaw) * Math.cos(p) * cam.d);
    camera.lookAt(cam.tx, ty, cam.tz);
  }
  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  function pickGround() {
    const o = ray.ray.origin, d = ray.ray.direction; if (d.y >= 0) return null;
    let t0 = Math.max(0, (o.y - 3) / -d.y), prev = t0;
    for (let t = t0; t < t0 + 120; t += 0.25) {
      const x = o.x + d.x * t, y = o.y + d.y * t, z = o.z + d.z * t;
      if (y <= gy(x, z)) { let a = prev, b = t; for (let k = 0; k < 8; k++) { const m = (a + b) / 2; if (o.y + d.y * m <= gy(o.x + d.x * m, o.z + d.z * m)) b = m; else a = m; } return [o.x + d.x * b, o.z + d.z * b]; }
      prev = t;
    }
    return null;
  }
  let portraits = {}, hovHex = null, hovUnit = null, mouse = null;
  function hoverAt(mx, my) {
    const rect = renderer.domElement.getBoundingClientRect();
    ndc.set((mx / rect.width) * 2 - 1, -(my / rect.height) * 2 + 1); ray.setFromCamera(ndc, camera);
    let u = null; const hit = ray.intersectObjects(unitRoots, true)[0]; if (hit) u = hit.object.userData.unit;
    const g = pickGround(); const h = g ? hexAt(g[0], g[1]) : null;
    if (!u && h && h.unit && !h.unit.anim) u = h.unit;
    if (h !== hovHex) {
      hovHex = h;
      if (h) { hoverRing.geometry.dispose(); hoverRing.geometry = ringGeo(h.x, h.z, 0.9, 0.98, 0.04); hoverFill.geometry.dispose(); hoverFill.geometry = patchGeo(h.x, h.z, 0.92, 0.035); }
      hoverRing.visible = hoverFill.visible = !!h;
      showPath(h);
      if (cb.onHex) {
        if (!h) cb.onHex(null);
        else {
          const T = TERRAIN[h.type], tags = [];
          if (h.road) tags.push('Droga'); if (h.river) tags.push('Rzeka · +1 ruch'); if (h.type === 'water') tags.push('Niedostępny');
          if (h.type === 'mountain') tags.push('Brak dla kołowych');
          const inReach = game.reach && game.reach.dist.has(h);
          cb.onHex({ name: T.name, city: h.city || '', coord: String(h.c + 1).padStart(2, '0') + '·' + String(h.r + 1).padStart(2, '0'), cost: T.cost === Infinity ? '—' : (h.road ? '1 (droga)' : String(T.cost)), def: h.type === 'water' ? '—' : '+' + T.def + '%', elev: Math.round(Math.max(h.h, 0) * 420 + 12) + ' m', tags, path: inReach ? game.reach.dist.get(h) + ' / ' + TYPES[game.sel.type].move + ' PR' : '' });
        }
      }
    }
    if (u !== hovUnit) { if (hovUnit) { hovUnit.hov = false; markerFill(hovUnit); } hovUnit = u; if (u) { u.hov = true; markerFill(u); } }
    cb.onHover && cb.onHover(u ? Object.assign(unitInfo(u, portraits), { x: mx, y: my }) : null);
  }
  function click(button) {
    if (button === 2) { select(null); return; }
    const h = hovHex; if (!h) { select(null); return; }
    const u = h.unit;
    if (u && u.f === game.active && !u.moved && !u.anim) { select(game.sel === u ? null : u); }
    else if (game.sel && game.reach && game.reach.dist.has(h)) moveUnit(game.sel, h);
    else select(null);
    if (mouse) { hovHex = null; hoverAt(mouse[0], mouse[1]); }
  }
  function endTurn() {
    select(null);
    game.active = 1 - game.active; if (game.active === 0) game.turn++;
    units.forEach(u => { u.moved = false; placeMarker(u); });
    emitState(); if (mouse) { hovHex = null; hoverAt(mouse[0], mouse[1]); }
  }

  const el = renderer.domElement; let down = null;
  const onDown = e => { down = { x: e.clientX, y: e.clientY, lx: e.clientX, ly: e.clientY, b: e.button, moved: false }; el.setPointerCapture(e.pointerId); };
  const onMove = e => {
    const rect = el.getBoundingClientRect(); mouse = [e.clientX - rect.left, e.clientY - rect.top];
    if (down) {
      if (Math.hypot(e.clientX - down.x, e.clientY - down.y) > 4) down.moved = true;
      const dx = e.clientX - down.lx, dy = e.clientY - down.ly; down.lx = e.clientX; down.ly = e.clientY;
      if (down.moved) {
        if (down.b === 2) cam.yaw -= dx * 0.005;
        else { const s = cam.d * 0.0016, cy = Math.cos(cam.yaw), sy = Math.sin(cam.yaw); cam.tx -= cy * dx * s - sy * dy * s; cam.tz -= -sy * dx * s - cy * dy * s; }
        if (cb.onHover) cb.onHover(null);
        return;
      }
    }
    hoverAt(mouse[0], mouse[1]);
  };
  const onUp = e => { if (down && !down.moved) click(down.b); down = null; try { el.releasePointerCapture(e.pointerId); } catch (_) { } };
  const onLeave = () => { mouse = null; hovHex = null; hoverRing.visible = hoverFill.visible = false; dots.count = 0; cb.onHover && cb.onHover(null); cb.onHex && cb.onHex(null); };
  const onWheel = e => { e.preventDefault(); cam.d = Math.max(7, Math.min(46, cam.d * (1 + e.deltaY * 0.0012))); };
  const onCtx = e => e.preventDefault();
  const onKey = e => { if (e.target && /input|textarea/i.test(e.target.tagName)) return; if (e.type === 'keydown') { if (e.key === 'Enter') endTurn(); else if (e.key === 'Escape') select(null); else keys.add(e.key.toLowerCase()); } else keys.delete(e.key.toLowerCase()); };
  el.addEventListener('pointerdown', onDown); el.addEventListener('pointermove', onMove); el.addEventListener('pointerup', onUp);
  el.addEventListener('pointerleave', onLeave); el.addEventListener('wheel', onWheel, { passive: false }); el.addEventListener('contextmenu', onCtx);
  addEventListener('keydown', onKey); addEventListener('keyup', onKey);

  const resize = () => { const w = container.clientWidth, h = container.clientHeight; renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix(); };
  const ro = new ResizeObserver(resize); ro.observe(container); resize();

  const clock = new THREE.Clock(), v = new THREE.Vector3(); let raf;
  function placeLabel(elm, p) {
    v.copy(p).project(camera);
    if (v.z > 1) { elm.style.display = 'none'; return; }
    elm.style.display = ''; elm.style.transform = `translate(${(v.x * 0.5 + 0.5) * container.clientWidth}px,${(-v.y * 0.5 + 0.5) * container.clientHeight}px)`;
  }
  function loop() {
    raf = requestAnimationFrame(loop);
    const dt = Math.min(0.05, clock.getDelta());
    const ps = cam.d * 0.9 * dt, cy = Math.cos(cam.yaw), sy = Math.sin(cam.yaw);
    if (keys.has('w') || keys.has('arrowup')) { cam.tx -= sy * ps; cam.tz -= cy * ps; }
    if (keys.has('s') || keys.has('arrowdown')) { cam.tx += sy * ps; cam.tz += cy * ps; }
    if (keys.has('a') || keys.has('arrowleft')) { cam.tx -= cy * ps; cam.tz += sy * ps; }
    if (keys.has('d') || keys.has('arrowright')) { cam.tx += cy * ps; cam.tz -= sy * ps; }
    if (keys.has('q')) cam.yaw += dt * 1.2; if (keys.has('e')) cam.yaw -= dt * 1.2;
    updateCamera();
    for (const u of units) {
      if (u.anim) {
        const A = u.anim; A.t += dt / 0.26;
        while (A.t >= 1 && A.i < A.path.length - 1) { A.t -= 1; A.i++; }
        if (A.i >= A.path.length - 1) { u.root.position.copy(A.path[A.path.length - 1]); u.anim = null; u.ring.visible = u.fill.visible = true; placeMarker(u); }
        else {
          const a = A.path[A.i], b = A.path[A.i + 1]; u.root.position.lerpVectors(a, b, A.t);
          const target = Math.atan2(-(b.z - a.z), b.x - a.x); let dr = target - u.root.rotation.y; dr = Math.atan2(Math.sin(dr), Math.cos(dr)); u.root.rotation.y += dr * Math.min(1, dt * 14);
        }
      }
      u.lp.copy(u.root.position); u.lp.y += TYPES[u.type].y; placeLabel(u.label, u.lp);
      u.label.style.opacity = u.moved && u.f === game.active ? 0.55 : 1;
    }
    cityLabels.forEach(l => placeLabel(l.el, l.p));
    hoverRing.material.opacity = 0.6 + Math.sin(performance.now() / 260) * 0.25;
    renderer.render(scene, camera);
  }
  loop();
  emitState();
  setTimeout(() => { try { portraits = makePortraits(); } catch (e) { console.warn(e); } cb.onReady && cb.onReady(); }, 30);

  return {
    endTurn,
    dispose() {
      cancelAnimationFrame(raf); ro.disconnect(); removeEventListener('keydown', onKey); removeEventListener('keyup', onKey);
      renderer.dispose(); el.remove(); labels.innerHTML = '';
    },
  };
}
