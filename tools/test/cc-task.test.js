const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { parseFrontmatter } = require('./frontmatter');

const BIN = path.join(__dirname, '..', 'bin', 'cc-task');

function setup() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-task-'));
  fs.mkdirSync(path.join(home, 'sessions'));
  fs.writeFileSync(path.join(home, 'sessions', '4242.json'), JSON.stringify({
    pid: 4242, sessionId: 'sid-4242', cwd: '/Users/dev/Development/lumen/worktrees/x', name: 'lu.01',
  }));
  return home;
}

function run(home, args, env = {}) {
  return spawnSync('sh', [BIN, ...args], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: os.homedir(), CC_HOME: home, CLAUDE_PID: '4242', CC_DEV_ROOT: '/Users/dev/Development', ...env },
  });
}

const read = (home, name = 'lu.01') => fs.readFileSync(path.join(home, 'handover', `${name}.md`), 'utf8');

test('creates file with frontmatter and template', () => {
  const home = setup();
  const r = run(home, ['rework layout']);
  assert.equal(r.status, 0, r.stderr);
  const { fields, body } = parseFrontmatter(read(home));
  assert.equal(fields.session, 'lu.01');
  assert.equal(fields.project, 'lumen');
  assert.equal(fields.task, 'rework layout');
  assert.equal(fields.state, 'working');
  assert.match(fields.updated, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$/);
  assert.match(body, /^# Handover lu\.01\n\n## Lage\n\n## Offen\n\n## Regeln und Lehren\n$/);
});

test('updates fields, body stays byte-identical, other fields are kept', () => {
  const home = setup();
  fs.mkdirSync(path.join(home, 'handover'));
  const body = '# My body\n\nline without trailing newline';
  fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), `---\nsession: lu.01\nproject: old\nextra: kept\ntask: old\nstate: blocked\nupdated: 2020-01-01T00:00:00+00:00\n---\n${body}`);
  const r = run(home, ['new']);
  assert.equal(r.status, 0, r.stderr);
  const { fields, body: b2 } = parseFrontmatter(read(home));
  assert.equal(fields.task, 'new');
  assert.equal(fields.state, 'blocked', 'state without argument is kept');
  assert.equal(fields.project, 'old', 'existing project is kept');
  assert.equal(fields.extra, 'kept');
  assert.equal(b2, body);
});

test('--body replaces the body, --archive stores a copy', () => {
  const home = setup();
  run(home, ['first']);
  const nb = path.join(home, 'new.md');
  fs.writeFileSync(nb, '# New\n');
  const r = run(home, ['--archive', '--body', nb, 'handover written', 'handover']);
  assert.equal(r.status, 0, r.stderr);
  const { fields, body } = parseFrontmatter(read(home));
  assert.equal(body, '# New\n');
  assert.equal(fields.state, 'handover');
  const arch = fs.readdirSync(path.join(home, 'handover', 'archive', 'lu.01'));
  assert.equal(arch.length, 1);
  assert.match(arch[0], /^\d{4}-\d\d-\d\dT\d\d-\d\d\.md$/);
  assert.match(fs.readFileSync(path.join(home, 'handover', 'archive', 'lu.01', arch[0]), 'utf8'), /task: first/);
});

test('--no-create without file: nothing, exit 0', () => {
  const home = setup();
  const r = run(home, ['--no-create', 'x']);
  assert.equal(r.status, 0);
  assert.equal(fs.existsSync(path.join(home, 'handover', 'lu.01.md')), false);
});

test('no name → exit 1 with hint', () => {
  const home = setup();
  const r = run(home, ['x'], { CLAUDE_PID: '9999' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /claude -n/);
});

test('--name writes another session\'s file; unknown session → project empty', () => {
  const home = setup();
  const r = run(home, ['--name', 'or.02', 'other', 'done']);
  assert.equal(r.status, 0, r.stderr);
  const { fields } = parseFrontmatter(read(home, 'or.02'));
  assert.equal(fields.session, 'or.02');
  assert.equal(fields.project, '');
  assert.equal(fields.state, 'done');
});

test('line breaks in the task become spaces, backslashes are kept', () => {
  const home = setup();
  run(home, ['a\nb \\n c']);
  assert.equal(parseFrontmatter(read(home)).fields.task, 'a b \\n c');
});

test('task line longer than 4 words or 40 characters → exit 2, file untouched', () => {
  const home = setup();
  for (const long of ['fix the login bug today', 'Überarbeitungdesgesamtenanmeldeformulars-x']) {
    const r = run(home, [long]);
    assert.equal(r.status, 2, long);
    assert.match(r.stderr, /at most 4 words/);
  }
  assert.equal(fs.existsSync(path.join(home, 'handover', 'lu.01.md')), false);
});

test('short task lines pass, umlauts count as one character', () => {
  const home = setup();
  for (const ok of ['New iPhone build (or.pm)', 'neu gestartet, Handover gelesen', 'Überprüfung Größenänderung äöü']) {
    assert.equal(run(home, [ok]).status, 0, ok);
  }
});

test('--detail writes a detail line; the next call without --detail clears it', () => {
  const home = setup();
  let r = run(home, ['--detail', 'enter the FCM key\nfor prod, then test build 214', 'Android app']);
  assert.equal(r.status, 0, r.stderr);
  let { fields } = parseFrontmatter(read(home));
  assert.equal(fields.task, 'Android app');
  assert.equal(fields.detail, 'enter the FCM key for prod, then test build 214');
  r = run(home, ['Android app', 'done']);
  ({ fields } = parseFrontmatter(read(home)));
  assert.equal(fields.detail, undefined);
});

test('--detail longer than 120 characters → exit 2', () => {
  const home = setup();
  const r = run(home, ['--detail', 'x'.repeat(121), 'Android app']);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /detail/);
});
