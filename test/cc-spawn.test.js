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

test('baut den Startbefehl mit Verzeichnis, Name und optionalem Auftrag', () => {
  const home = setup();
  const dir = fs.realpathSync(os.tmpdir());
  assert.equal(run(home, ['lu.01', dir]).stdout, `cd ${dir} && claude -n lu.01\n`);
  assert.equal(run(home, ['lu.01', dir, 'mach X']).stdout, `cd ${dir} && claude -n lu.01 mach X\n`);
});

test('lehnt ab, wenn der Name schon läuft; tote Einträge zählen nicht', () => {
  const live = setup([{ pid: process.pid, name: 'lu.01' }]);
  const r = run(live, ['lu.01', os.tmpdir()]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /läuft schon/);
  const dead = setup([{ pid: 999999, name: 'lu.01' }]);
  assert.equal(run(dead, ['lu.01', os.tmpdir()]).status, 0);
});

test('ungültiger Name, fehlendes Verzeichnis, falsche Argumente → 2', () => {
  const home = setup();
  assert.equal(run(home, ['a/b', os.tmpdir()]).status, 2);
  assert.equal(run(home, ['lu.01', '/gibt/es/nicht']).status, 2);
  assert.equal(run(home, ['lu.01']).status, 2);
});
