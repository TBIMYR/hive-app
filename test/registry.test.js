const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { readRegistry } = require('../lib/registry');

const DIR = path.join(__dirname, 'fixtures', 'sessions');
const allAlive = () => true;

test('liest Einträge, überspringt defekte Dateien', () => {
  const r = readRegistry(DIR, { isAlive: allAlive });
  assert.equal(r.entries.length, 4);
  assert.equal(r.errors.length, 1);
  assert.match(r.errors[0], /broken\.json/);
});

test('Felder werden übernommen, waitingFor optional', () => {
  const r = readRegistry(DIR, { isAlive: allAlive });
  const pm = r.entries.find(e => e.pid === 100);
  assert.equal(pm.name, 'lu.pm');
  assert.equal(pm.sessionId, 'sid-100');
  assert.equal(pm.status, 'idle');
  assert.equal(pm.waitingFor, null);
  assert.equal(pm.alive, true);
  assert.equal(pm.statusUpdatedAt, new Date(5000).toISOString());
  const w = r.entries.find(e => e.pid === 101);
  assert.equal(w.waitingFor, 'input needed');
});

test('Duplikat-Name: jüngstes startedAt behält den Namen', () => {
  const r = readRegistry(DIR, { isAlive: allAlive });
  const names = r.entries.map(e => e.name).sort();
  assert.deepEqual(names, ['lu.01', 'lu.01#101', 'lu.pm', 'lu.pm#103']);
  assert.equal(r.entries.find(e => e.name === 'lu.01').pid, 102);
});

test('Duplikat-Name: Session mit Fenster schlägt jüngere Hintergrund-Session', () => {
  const r = readRegistry(DIR, { isAlive: allAlive });
  assert.equal(r.entries.find(e => e.name === 'lu.pm').pid, 100);
  const bg = r.entries.find(e => e.pid === 103);
  assert.equal(bg.name, 'lu.pm#103');
  assert.equal(bg.kind, 'bg');
  assert.equal(r.entries.find(e => e.pid === 100).kind, 'interactive');
});

test('Duplikat-Name: tote Einträge zählen nicht', () => {
  const r = readRegistry(DIR, { isAlive: pid => pid !== 102 });
  assert.equal(r.entries.find(e => e.pid === 101).name, 'lu.01');
});

test('tote Prozesse werden als alive=false markiert', () => {
  const r = readRegistry(DIR, { isAlive: pid => pid !== 101 });
  assert.equal(r.entries.find(e => e.pid === 101).alive, false);
});

test('fehlendes Verzeichnis → leer, kein Fehler', () => {
  const r = readRegistry('/nonexistent/dir', { isAlive: allAlive });
  assert.deepEqual(r.entries, []);
});
