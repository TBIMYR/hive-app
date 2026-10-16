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

test('without handover file: no output, no file, but marker, exit 0', () => {
  const home = setup();
  const r = run(home);
  assert.equal(r.status, 0);
  assert.equal(r.stdout, '');
  assert.equal(fs.existsSync(path.join(home, 'handover', 'lu.01.md')), false);
  assert.ok(fs.existsSync(path.join(home, 'handover', '.loaded', 'sid-4242')), 'marker is set on first name resolution');
});

test('a file the session creates itself later is not loaded as predecessor', () => {
  const home = setup();
  run(home);
  const r1 = spawnSync('sh', [CC_TASK, 'own task'], {
    encoding: 'utf8', env: { PATH: process.env.PATH, HOME: os.homedir(), CC_HOME: home, CLAUDE_PID: '4242' },
  });
  assert.equal(r1.status, 0, r1.stderr);
  const r = run(home);
  assert.equal(r.stdout, '');
  assert.match(fs.readFileSync(path.join(home, 'handover', 'lu.01.md'), 'utf8'), /task: own task/);
});

test('with handover file: print content, set task line, create marker', () => {
  const home = setup();
  fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), '---\nsession: lu.01\ntask: old\nstate: handover\n---\n# Handover lu.01\nContent\n');
  const r = run(home);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Handover of the predecessor session lu\.01/);
  assert.match(r.stdout, /Content/);
  const f = fs.readFileSync(path.join(home, 'handover', 'lu.01.md'), 'utf8');
  assert.match(f, /task: restarted, handover read/);
  assert.match(f, /state: working/);
  assert.ok(fs.existsSync(path.join(home, 'handover', '.loaded', 'sid-4242')));
});

test('second call from the same session: nothing', () => {
  const home = setup();
  fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), '---\nsession: lu.01\ntask: old\n---\nx\n');
  run(home);
  const r = run(home);
  assert.equal(r.stdout, '');
});

test('name not yet known: nothing, no marker (retried on the next prompt)', () => {
  const home = setup({ named: false });
  const r = run(home);
  assert.equal(r.status, 0);
  assert.equal(r.stdout, '');
  assert.equal(fs.existsSync(path.join(home, 'handover', '.loaded', 'sid-4242')), false);
});

test('derived name (nameSource derived): nothing', () => {
  const home = setup({ derived: true });
  fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), '---\nsession: lu.01\ntask: old\n---\nx\n');
  assert.equal(run(home).stdout, '');
});

test('without CLAUDE_PID: find registry entry via session_id', () => {
  const home = setup();
  fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), '---\nsession: lu.01\ntask: old\n---\nContent\n');
  const r = run(home, { CLAUDE_PID: '' });
  assert.match(r.stdout, /Content/);
});
