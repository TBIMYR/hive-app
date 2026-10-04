const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { createServer } = require('../server');

const HOME = path.join(__dirname, 'fixtures');

async function withServer(fn, focusPid) {
  const srv = createServer({ claudeHome: HOME, isAlive: () => true, focusPid });
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${srv.address().port}`;
  try { await fn(base); } finally { await new Promise(r => srv.close(r)); }
}

test('GET / serves HTML', () => withServer(async base => {
  const res = await fetch(base + '/');
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /text\/html/);
  assert.match(await res.text(), /<html/i);
}));

test('GET /api/state returns sessions', () => withServer(async base => {
  const res = await fetch(base + '/api/state');
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.ok(Array.isArray(j.sessions));
  assert.ok(j.sessions.some(s => s.name === 'lu.pm'));
  assert.ok(j.generatedAt);
}));

test('GET /api/handover/<name> returns Markdown, 404 if missing, 400 for invalid name', () => withServer(async base => {
  const ok = await fetch(base + '/api/handover/lu.01');
  assert.equal(ok.status, 200);
  assert.match(ok.headers.get('content-type'), /text\/markdown/);
  assert.match(await ok.text(), /Handover lu\.01/);
  assert.equal((await fetch(base + '/api/handover/unbekannt')).status, 404);
  assert.equal((await fetch(base + '/api/handover/..%2Fsessions%2F100')).status, 400);
  assert.equal((await fetch(base + '/api/handover/a%2Fb')).status, 400);
}));

test('unknown route → 404', () => withServer(async base => {
  assert.equal((await fetch(base + '/nope')).status, 404);
}));

test('icons are served, other files under /icons/ are not', () => withServer(async base => {
  const touch = await fetch(base + '/apple-touch-icon.png');
  assert.equal(touch.status, 200);
  assert.equal(touch.headers.get('content-type'), 'image/png');
  const svg = await fetch(base + '/icons/hive.svg');
  assert.equal(svg.status, 200);
  assert.match(await svg.text(), /<svg/);
  assert.equal((await fetch(base + '/icons/../server.js')).status, 404);
  assert.equal((await fetch(base + '/icons/nope.png')).status, 404);
}));

test('POST /api/focus/<pid> calls focusPid for a live session with a window', async () => {
  const calls = [];
  await withServer(async base => {
    const res = await fetch(base + '/api/focus/100', { method: 'POST' });
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { ok: true, tty: '/dev/ttys001' });
  }, async pid => { calls.push(pid); return { ok: true, tty: '/dev/ttys001' }; });
  assert.deepEqual(calls, [100]);
});

test('focus: background session → 409, unknown PID → 404, garbage → 400, GET → 405', async () => {
  const calls = [];
  await withServer(async base => {
    assert.equal((await fetch(base + '/api/focus/103', { method: 'POST' })).status, 409);
    assert.equal((await fetch(base + '/api/focus/999', { method: 'POST' })).status, 404);
    assert.equal((await fetch(base + '/api/focus/abc', { method: 'POST' })).status, 400);
    assert.equal((await fetch(base + '/api/focus/100')).status, 405);
  }, async pid => { calls.push(pid); return { ok: true }; });
  assert.deepEqual(calls, []);
});

test('focus: foreign origin → 403', async () => {
  await withServer(async base => {
    const res = await fetch(base + '/api/focus/100', { method: 'POST', headers: { origin: 'https://evil.example' } });
    assert.equal(res.status, 403);
  }, async () => ({ ok: true }));
});

test('focus: failure is reported as 422 with reason', async () => {
  await withServer(async base => {
    const res = await fetch(base + '/api/focus/100', { method: 'POST' });
    assert.equal(res.status, 422);
    assert.match((await res.json()).reason, /no iTerm tab/);
  }, async () => ({ ok: false, reason: 'no iTerm tab for /dev/ttys001' }));
});
