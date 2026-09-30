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

test('GET / liefert HTML', () => withServer(async base => {
  const res = await fetch(base + '/');
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /text\/html/);
  assert.match(await res.text(), /<html/i);
}));

test('GET /api/state liefert Sessions', () => withServer(async base => {
  const res = await fetch(base + '/api/state');
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.ok(Array.isArray(j.sessions));
  assert.ok(j.sessions.some(s => s.name === 'lu.pm'));
  assert.ok(j.generatedAt);
}));

test('GET /api/handover/<name> liefert Markdown, 404 wenn fehlend, 400 bei ungültigem Namen', () => withServer(async base => {
  const ok = await fetch(base + '/api/handover/lu.01');
  assert.equal(ok.status, 200);
  assert.match(ok.headers.get('content-type'), /text\/markdown/);
  assert.match(await ok.text(), /Handover lu\.01/);
  assert.equal((await fetch(base + '/api/handover/unbekannt')).status, 404);
  assert.equal((await fetch(base + '/api/handover/..%2Fsessions%2F100')).status, 400);
  assert.equal((await fetch(base + '/api/handover/a%2Fb')).status, 400);
}));

test('unbekannte Route → 404', () => withServer(async base => {
  assert.equal((await fetch(base + '/nope')).status, 404);
}));

test('POST /api/focus/<pid> ruft focusPid für lebende Session mit Fenster', async () => {
  const calls = [];
  await withServer(async base => {
    const res = await fetch(base + '/api/focus/100', { method: 'POST' });
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { ok: true, tty: '/dev/ttys001' });
  }, async pid => { calls.push(pid); return { ok: true, tty: '/dev/ttys001' }; });
  assert.deepEqual(calls, [100]);
});

test('focus: Hintergrund-Session → 409, unbekannte PID → 404, Unsinn → 400, GET → 405', async () => {
  const calls = [];
  await withServer(async base => {
    assert.equal((await fetch(base + '/api/focus/103', { method: 'POST' })).status, 409);
    assert.equal((await fetch(base + '/api/focus/999', { method: 'POST' })).status, 404);
    assert.equal((await fetch(base + '/api/focus/abc', { method: 'POST' })).status, 400);
    assert.equal((await fetch(base + '/api/focus/100')).status, 405);
  }, async pid => { calls.push(pid); return { ok: true }; });
  assert.deepEqual(calls, []);
});

test('focus: fremder Origin → 403', async () => {
  await withServer(async base => {
    const res = await fetch(base + '/api/focus/100', { method: 'POST', headers: { origin: 'https://evil.example' } });
    assert.equal(res.status, 403);
  }, async () => ({ ok: true }));
});

test('focus: Fehlschlag wird als 422 mit Grund gemeldet', async () => {
  await withServer(async base => {
    const res = await fetch(base + '/api/focus/100', { method: 'POST' });
    assert.equal(res.status, 422);
    assert.match((await res.json()).reason, /kein iTerm-Tab/);
  }, async () => ({ ok: false, reason: 'kein iTerm-Tab mit /dev/ttys001' }));
});
