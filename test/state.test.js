const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { buildState } = require('../lib/state');

const HOME = path.join(__dirname, 'fixtures');
const DEV = '/Users/dev/Development';
const NOW = new Date('2026-09-30T16:00:00Z');

function build(overrides = {}) {
  return buildState({ claudeHome: HOME, devRoot: DEV, now: NOW, isAlive: () => true, ...overrides });
}

test('live sessions + offline row from handover, each name once', () => {
  const s = build();
  const names = s.sessions.map(x => x.name);
  assert.deepEqual([...names].sort(), ['lu.01', 'lu.01#101', 'lu.pm', 'lu.pm#103', 'or.pm']);
  const off = s.sessions.find(x => x.name === 'or.pm');
  assert.equal(off.alive, false);
  assert.equal(off.status, 'offline');
  assert.equal(off.task.text, 'Handover geschrieben, wartet auf Neustart');
  assert.equal(off.project, 'orbit');
});

test('transcript fields and handover are joined', () => {
  const pm = build().sessions.find(x => x.name === 'lu.pm');
  assert.equal(pm.lastAssistant.text, 'Ich fange mit dem Layout an.');
  assert.equal(pm.branch, 'feat/kalender');
  assert.equal(pm.project, 'lumen');
  assert.equal(pm.group, 'lu');
  assert.equal(pm.isPm, true);
  assert.equal(pm.hasHandover, false);
  assert.equal(pm.task, null);
  const w = build().sessions.find(x => x.name === 'lu.01');
  assert.equal(w.hasHandover, true);
  assert.equal(w.task.state, 'working');
  assert.equal(w.lastAssistant, null, 'no transcript for sid-102 → null, no error');
});

test('stale: busy and task older than 60 min', () => {
  const s = build({ now: new Date('2026-09-30T18:00:00+02:00') });
  const w = s.sessions.find(x => x.name === 'lu.01');
  assert.equal(w.status, 'busy');
  assert.equal(w.task.stale, true);
  const s2 = build({ now: new Date('2026-09-30T16:30:00+02:00') });
  assert.equal(s2.sessions.find(x => x.name === 'lu.01').task.stale, false);
});

test('sorting: group, PM first, then name', () => {
  const s = build();
  assert.deepEqual(s.sessions.map(x => x.name), ['lu.pm', 'lu.01', 'lu.01#101', 'lu.pm#103', 'or.pm']);
});

test('dead registry entries without handover are dropped', () => {
  const s = build({ isAlive: pid => pid !== 100 && pid !== 103 });
  assert.equal(s.sessions.find(x => x.name.startsWith('lu.pm')), undefined);
});

test('kind is passed through, offline rows have kind null', () => {
  const s = build();
  assert.equal(s.sessions.find(x => x.name === 'lu.pm').kind, 'interactive');
  assert.equal(s.sessions.find(x => x.name === 'lu.pm#103').kind, 'bg');
  assert.equal(s.sessions.find(x => x.name === 'or.pm').kind, null);
});
