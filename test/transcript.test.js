const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { readTail, parseTail } = require('../lib/transcript');

const FILE = path.join(__dirname, 'fixtures', 'transcript.jsonl');

test('parseTail: last assistant text reply, not tool_use/thinking', () => {
  const r = parseTail(fs.readFileSync(FILE, 'utf8'));
  assert.equal(r.lastAssistant.text, 'Ich fange mit dem Layout an.');
  assert.equal(r.lastAssistant.at, '2026-09-30T10:00:02.000Z');
});

test('parseTail: last real prompt, not isMeta, not <…>, not tool_result', () => {
  const r = parseTail(fs.readFileSync(FILE, 'utf8'));
  assert.equal(r.lastUser.text, 'Bitte die Kalender-Ansicht umbauen');
});

test('parseTail: branch from the newest line with gitBranch', () => {
  const r = parseTail(fs.readFileSync(FILE, 'utf8'));
  assert.equal(r.branch, 'feat/kalender');
});

test('parseTail: empty text → null fields', () => {
  assert.deepEqual(parseTail(''), { lastAssistant: null, lastUser: null, branch: null });
});

test('readTail: reads at most N bytes and cuts at a line boundary', () => {
  const t = readTail(FILE, 200);
  assert.ok(Buffer.byteLength(t) <= 200);
  assert.ok(!t.startsWith('{') || t.split('\n')[0].startsWith('{"type"'), 'first line complete or discarded');
  const full = readTail(FILE, 1 << 20);
  assert.equal(full, fs.readFileSync(FILE, 'utf8'));
});

test('readTail: missing file → empty string', () => {
  assert.equal(readTail('/nonexistent.jsonl', 100), '');
});
