const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const BIN = path.join(__dirname, '..', 'bin', 'cc-spawn');

function setup(entries = []) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-spawn-'));
  fs.mkdirSync(path.join(home, 'sessions'));
  for (const e of entries) fs.writeFileSync(path.join(home, 'sessions', `${e.pid}.json`), JSON.stringify(e));
  return home;
}

const run = (home, args) => spawnSync('sh', [BIN, ...args], {
  encoding: 'utf8',
  env: { PATH: process.env.PATH, HOME: os.homedir(), CC_HOME: home, CC_SPAWN_DRYRUN: '1' },
});

test('builds the start command with directory, name and optional task', () => {
  const home = setup();
  const dir = fs.realpathSync(os.tmpdir());
  assert.equal(run(home, ['lu.01', dir]).stdout, `[iterm] cd ${dir} && claude -n lu.01\n`);
  assert.equal(run(home, ['lu.01', dir, 'do X']).stdout, `[iterm] cd ${dir} && claude -n lu.01 do X\n`);
});

test('target: hive when the caller runs in the app\'s tmux server, or via CC_SPAWN_TARGET', () => {
  const home = setup();
  const dir = fs.realpathSync(os.tmpdir());
  const r = (env) => spawnSync('sh', [BIN, 'lu.01', dir], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: os.homedir(), CC_HOME: home, CC_SPAWN_DRYRUN: '1', ...env },
  });
  assert.match(r({ TMUX: '/private/tmp/tmux-501/hive,123,0' }).stdout, /^\[hive\]/);
  assert.match(r({ TMUX: '/private/tmp/tmux-501/default,123,0' }).stdout, /^\[iterm\]/);
  assert.match(r({ CC_SPAWN_TARGET: 'hive' }).stdout, /^\[hive\]/);
  assert.equal(r({ CC_SPAWN_TARGET: 'nonsense' }).status, 2);
});

test('refuses if the name is already running; dead entries do not count', () => {
  const live = setup([{ pid: process.pid, name: 'lu.01' }]);
  const r = run(live, ['lu.01', os.tmpdir()]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /already running/);
  const dead = setup([{ pid: 999999, name: 'lu.01' }]);
  assert.equal(run(dead, ['lu.01', os.tmpdir()]).status, 0);
});

test('invalid name, missing directory, wrong arguments → 2', () => {
  const home = setup();
  assert.equal(run(home, ['a/b', os.tmpdir()]).status, 2);
  assert.equal(run(home, ['lu.01', '/does/not/exist']).status, 2);
  assert.equal(run(home, ['lu.01']).status, 2);
});
