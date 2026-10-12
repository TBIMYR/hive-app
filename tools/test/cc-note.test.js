const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const BIN = path.join(__dirname, '..', 'bin', 'cc-note');

function setup() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-note-'));
  fs.mkdirSync(path.join(home, 'sessions'));
  fs.writeFileSync(path.join(home, 'sessions', '4242.json'), JSON.stringify({
    pid: 4242, sessionId: 'sid-4242', cwd: '/Users/dev/Development/lumen', name: 'lu.01',
  }));
  return home;
}

function run(home, args, { input, env = {} } = {}) {
  return spawnSync('sh', [BIN, ...args], {
    encoding: 'utf8',
    input: input ?? '',
    env: { PATH: process.env.PATH, HOME: os.homedir(), CC_HOME: home, CLAUDE_PID: '4242', ...env },
  });
}

function notes(home, name = 'lu.01') {
  const file = path.join(home, 'hive', 'notes', `${name}.md`);
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
}

function leftovers(home) {
  const dir = path.join(home, 'hive', 'notes');
  return fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.startsWith('.')) : [];
}

test('writes the text into the calling session\'s notepad', () => {
  const home = setup();
  const r = run(home, ['Run `make seed` first\nthen restart the server']);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /added to the notes of lu\.01/);
  assert.equal(notes(home), 'Run `make seed` first\nthen restart the server\n');
  assert.deepEqual(leftovers(home), []);
});

test('appends below what is there, set apart by a line', () => {
  const home = setup();
  assert.equal(run(home, ['first']).status, 0);
  assert.equal(run(home, ['second\nline']).status, 0);
  assert.equal(notes(home), 'first\n\n---\n\nsecond\nline\n');
  // a notepad that was emptied starts fresh
  fs.writeFileSync(path.join(home, 'hive', 'notes', 'lu.01.md'), '\n');
  assert.equal(run(home, ['third']).status, 0);
  assert.equal(notes(home), 'third\n');
  assert.deepEqual(leftovers(home), []);
});

test('reads the text from stdin and keeps backslashes', () => {
  const home = setup();
  const r = run(home, [], { input: '# Steps\n\n1. open C:\\temp\\n\n2. done\n' });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(notes(home), '# Steps\n\n1. open C:\\temp\\n\n2. done\n');
  assert.equal(run(home, ['-'], { input: 'via dash\n' }).status, 0);
  assert.match(notes(home), /done\n\n---\n\nvia dash\n$/);
});

test('--name writes to another session', () => {
  const home = setup();
  const r = run(home, ['--name', 'or.pm', 'for the PM'], { env: { CLAUDE_PID: '' } });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(notes(home, 'or.pm'), 'for the PM\n');
  assert.equal(notes(home), null);
});

test('rejects empty notes, unknown sessions and unsafe names', () => {
  const home = setup();
  assert.equal(run(home, ['  \n ']).status, 2);
  assert.equal(run(home, [], { input: '\n' }).status, 2);
  assert.equal(notes(home), null);
  assert.deepEqual(leftovers(home), []);
  assert.equal(run(home, ['text'], { env: { CLAUDE_PID: '' } }).status, 1);
  assert.equal(run(home, ['--name', '../x', 'text']).status, 2);
  assert.equal(run(home, ['--name', 'a/b', 'text']).status, 2);
  assert.equal(run(home, ['one', 'two']).status, 2);
  assert.ok(!fs.existsSync(path.join(home, 'hive', 'x.md')));
});
