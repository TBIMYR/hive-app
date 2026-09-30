const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const BIN = path.join(__dirname, '..', 'bin', 'cc-handover-load');
const CC_TASK = path.join(__dirname, '..', 'bin', 'cc-task');

function setup({ named = true, derived = false } = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-load-'));
  fs.mkdirSync(path.join(home, 'sessions'));
  fs.mkdirSync(path.join(home, 'handover'));
  fs.writeFileSync(path.join(home, 'sessions', '4242.json'), JSON.stringify({
    pid: 4242, sessionId: 'sid-4242', cwd: '/Users/dev/Development/lumen',
    ...(named ? { name: 'lu.01', nameSource: derived ? 'derived' : 'user' } : {}),
  }));
  return home;
}

function run(home, env = {}, input = '{"session_id":"sid-4242","hook_event_name":"SessionStart"}') {
  return spawnSync('sh', [BIN], {
    encoding: 'utf8', input,
    env: { PATH: process.env.PATH, HOME: os.homedir(), CC_HOME: home, CC_TASK, CLAUDE_PID: '4242', ...env },
  });
}

test('ohne Handover-Datei: keine Ausgabe, keine Datei, Exit 0', () => {
  const home = setup();
  const r = run(home);
  assert.equal(r.status, 0);
  assert.equal(r.stdout, '');
  assert.equal(fs.existsSync(path.join(home, 'handover', 'lu.01.md')), false);
});

test('mit Handover-Datei: Inhalt ausgeben, Aufgaben-Zeile setzen, Marker anlegen', () => {
  const home = setup();
  fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), '---\nsession: lu.01\ntask: alt\nstate: handover\n---\n# Handover lu.01\nInhalt\n');
  const r = run(home);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Handover der Vorgänger-Session lu\.01/);
  assert.match(r.stdout, /Inhalt/);
  const f = fs.readFileSync(path.join(home, 'handover', 'lu.01.md'), 'utf8');
  assert.match(f, /task: neu gestartet, Handover gelesen/);
  assert.match(f, /state: working/);
  assert.ok(fs.existsSync(path.join(home, 'handover', '.loaded', 'sid-4242')));
});

test('zweiter Aufruf derselben Session: nichts', () => {
  const home = setup();
  fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), '---\nsession: lu.01\ntask: alt\n---\nx\n');
  run(home);
  const r = run(home);
  assert.equal(r.stdout, '');
});

test('Name fehlt noch: nichts, kein Marker (wird beim nächsten Prompt erneut versucht)', () => {
  const home = setup({ named: false });
  const r = run(home);
  assert.equal(r.status, 0);
  assert.equal(r.stdout, '');
  assert.equal(fs.existsSync(path.join(home, 'handover', '.loaded', 'sid-4242')), false);
});

test('abgeleiteter Name (nameSource derived): nichts', () => {
  const home = setup({ derived: true });
  fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), '---\nsession: lu.01\ntask: alt\n---\nx\n');
  assert.equal(run(home).stdout, '');
});

test('ohne CLAUDE_PID: Register über session_id finden', () => {
  const home = setup();
  fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), '---\nsession: lu.01\ntask: alt\n---\nInhalt\n');
  const r = run(home, { CLAUDE_PID: '' });
  assert.match(r.stdout, /Inhalt/);
});
