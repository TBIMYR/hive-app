const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { readTail, parseTail } = require('../lib/transcript');

const FILE = path.join(__dirname, 'fixtures', 'transcript.jsonl');

test('parseTail: letzte Assistant-Textantwort, nicht tool_use/thinking', () => {
  const r = parseTail(fs.readFileSync(FILE, 'utf8'));
  assert.equal(r.lastAssistant.text, 'Ich fange mit dem Layout an.');
  assert.equal(r.lastAssistant.at, '2026-09-30T10:00:02.000Z');
});

test('parseTail: letzter echter Prompt, nicht isMeta, nicht <…>, nicht tool_result', () => {
  const r = parseTail(fs.readFileSync(FILE, 'utf8'));
  assert.equal(r.lastUser.text, 'Bitte die Kalender-Ansicht umbauen');
});

test('parseTail: Branch aus der jüngsten Zeile mit gitBranch', () => {
  const r = parseTail(fs.readFileSync(FILE, 'utf8'));
  assert.equal(r.branch, 'feat/kalender');
});

test('parseTail: leerer Text → null-Felder', () => {
  assert.deepEqual(parseTail(''), { lastAssistant: null, lastUser: null, branch: null });
});

test('readTail: liest höchstens N Bytes und schneidet an Zeilengrenze', () => {
  const t = readTail(FILE, 200);
  assert.ok(Buffer.byteLength(t) <= 200);
  assert.ok(!t.startsWith('{') || t.split('\n')[0].startsWith('{"type"'), 'erste Zeile vollständig oder verworfen');
  const full = readTail(FILE, 1 << 20);
  assert.equal(full, fs.readFileSync(FILE, 'utf8'));
});

test('readTail: fehlende Datei → leerer String', () => {
  assert.equal(readTail('/nonexistent.jsonl', 100), '');
});
