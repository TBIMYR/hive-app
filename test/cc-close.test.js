const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const BIN = path.join(__dirname, '..', 'bin', 'cc-close');

function setup(entry, handover = true) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-close-'));
  fs.mkdirSync(path.join(home, 'sessions'));
  fs.mkdirSync(path.join(home, 'handover'));
  if (entry) fs.writeFileSync(path.join(home, 'sessions', `${entry.pid}.json`), JSON.stringify(entry));
  if (handover) fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), '---\nsession: lu.01\n---\n');
  return home;
}

const run = (home, args, env = {}) => spawnSync('sh', [BIN, ...args], {
  encoding: 'utf8',
  env: { PATH: process.env.PATH, HOME: os.homedir(), CC_HOME: home, CC_CLOSE_DRYRUN: '1', CLAUDE_PID: '1', ...env },
});

test('no running session → 1', () => {
  assert.equal(run(setup(null), ['lu.01']).status, 1);
  assert.equal(run(setup({ pid: 999999, name: 'lu.01', status: 'idle' }), ['lu.01']).status, 1);
});

test('working session or missing handover only with --force', () => {
  const busy = setup({ pid: process.pid, name: 'lu.01', status: 'busy' });
  const r = run(busy, ['lu.01']);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /is working right now/);
  const shell = setup({ pid: process.pid, name: 'lu.01', status: 'shell' });
  const s = run(shell, ['lu.01']);
  assert.equal(s.status, 1);
  assert.match(s.stderr, /background tasks running/);
  assert.doesNotMatch(run(shell, ['--force', 'lu.01']).stderr, /background tasks running/);
  const noHo = setup({ pid: process.pid, name: 'lu.01', status: 'idle' }, false);
  assert.match(run(noHo, ['lu.01']).stderr, /has no handover/);
});

test('own session is refused', () => {
  const home = setup({ pid: process.pid, name: 'lu.01', status: 'idle' });
  const r = run(home, ['--force', 'lu.01'], { CLAUDE_PID: String(process.pid) });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /your own session/);
});

test('invalid name or wrong arguments → 2', () => {
  const home = setup(null);
  assert.equal(run(home, ['a/b']).status, 2);
  assert.equal(run(home, []).status, 2);
});
