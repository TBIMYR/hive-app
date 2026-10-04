const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { readRegistry } = require('../lib/registry');

const DIR = path.join(__dirname, 'fixtures', 'sessions');
const allAlive = () => true;

test('reads entries, skips broken files', () => {
  const r = readRegistry(DIR, { isAlive: allAlive });
  assert.equal(r.entries.length, 4);
  assert.equal(r.errors.length, 1);
  assert.match(r.errors[0], /broken\.json/);
});

test('fields are taken over, waitingFor optional', () => {
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

test('spare processes are not sessions', () => {
  const r = readRegistry(DIR, { isAlive: allAlive });
  assert.equal(r.entries.find(e => e.pid === 104), undefined);
});

test('tmuxPane: pane ID from the tmux field, otherwise null', () => {
  const r = readRegistry(DIR, { isAlive: allAlive });
  assert.equal(r.entries.find(e => e.pid === 100).tmuxPane, '%1');
  assert.equal(r.entries.find(e => e.pid === 101).tmuxPane, null);
});

test('duplicate name: newest startedAt keeps the name', () => {
  const r = readRegistry(DIR, { isAlive: allAlive });
  const names = r.entries.map(e => e.name).sort();
  assert.deepEqual(names, ['lu.01', 'lu.01#101', 'lu.pm', 'lu.pm#103']);
  assert.equal(r.entries.find(e => e.name === 'lu.01').pid, 102);
});

test('duplicate name: session with window beats newer background session', () => {
  const r = readRegistry(DIR, { isAlive: allAlive });
  assert.equal(r.entries.find(e => e.name === 'lu.pm').pid, 100);
  const bg = r.entries.find(e => e.pid === 103);
  assert.equal(bg.name, 'lu.pm#103');
  assert.equal(bg.kind, 'bg');
  assert.equal(r.entries.find(e => e.pid === 100).kind, 'interactive');
});

test('duplicate name: dead entries do not count', () => {
  const r = readRegistry(DIR, { isAlive: pid => pid !== 102 });
  assert.equal(r.entries.find(e => e.pid === 101).name, 'lu.01');
});

test('dead processes are marked alive=false', () => {
  const r = readRegistry(DIR, { isAlive: pid => pid !== 101 });
  assert.equal(r.entries.find(e => e.pid === 101).alive, false);
});

test('missing directory → empty, no error', () => {
  const r = readRegistry('/nonexistent/dir', { isAlive: allAlive });
  assert.deepEqual(r.entries, []);
});

test('window with handed-over conversation (parkedJobId): one session with the background session\'s status', () => {
  const r = readRegistry(path.join(__dirname, 'fixtures', 'sessions-parked'), { isAlive: allAlive });
  assert.equal(r.entries.length, 1);
  const e = r.entries[0];
  assert.equal(e.name, 'x.01');
  assert.equal(e.pid, 105);
  assert.equal(e.tmuxPane, '%5');
  assert.equal(e.status, 'waiting');
  assert.equal(e.waitingFor, 'input needed');
  assert.equal(e.statusUpdatedAt, new Date(2000).toISOString());
});
