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

test('lebende Sessions + Offline-Zeile aus Handover, jeder Name einmal', () => {
  const s = build();
  const names = s.sessions.map(x => x.name);
  assert.deepEqual([...names].sort(), ['lu.01', 'lu.01#101', 'lu.pm', 'lu.pm#103', 'or.pm']);
  const off = s.sessions.find(x => x.name === 'or.pm');
  assert.equal(off.alive, false);
  assert.equal(off.status, 'offline');
  assert.equal(off.task.text, 'Handover geschrieben, wartet auf Neustart');
  assert.equal(off.project, 'orbit');
});

test('Transkript-Felder und Handover werden verknüpft', () => {
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
  assert.equal(w.lastAssistant, null, 'kein Transkript für sid-102 → null, kein Fehler');
});

test('stale: busy und task älter als 60 min', () => {
  const s = build({ now: new Date('2026-09-30T18:00:00+02:00') });
  const w = s.sessions.find(x => x.name === 'lu.01');
  assert.equal(w.status, 'busy');
  assert.equal(w.task.stale, true);
  const s2 = build({ now: new Date('2026-09-30T16:30:00+02:00') });
  assert.equal(s2.sessions.find(x => x.name === 'lu.01').task.stale, false);
});

test('Sortierung: Gruppe, PM zuerst, dann Name', () => {
  const s = build();
  assert.deepEqual(s.sessions.map(x => x.name), ['lu.pm', 'lu.01', 'lu.01#101', 'lu.pm#103', 'or.pm']);
});

test('tote Register-Einträge ohne Handover fallen weg', () => {
  const s = build({ isAlive: pid => pid !== 100 && pid !== 103 });
  assert.equal(s.sessions.find(x => x.name.startsWith('lu.pm')), undefined);
});

test('kind wird durchgereicht, Offline-Zeilen haben kind null', () => {
  const s = build();
  assert.equal(s.sessions.find(x => x.name === 'lu.pm').kind, 'interactive');
  assert.equal(s.sessions.find(x => x.name === 'lu.pm#103').kind, 'bg');
  assert.equal(s.sessions.find(x => x.name === 'or.pm').kind, null);
});
