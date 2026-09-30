const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { parseFrontmatter } = require('../lib/handover');

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

test('legt Datei mit Frontmatter und Vorlage an', () => {
  const home = setup();
  const r = run(home, ['Layout umbauen']);
  assert.equal(r.status, 0, r.stderr);
  const { fields, body } = parseFrontmatter(read(home));
  assert.equal(fields.session, 'lu.01');
  assert.equal(fields.project, 'lumen');
  assert.equal(fields.task, 'Layout umbauen');
  assert.equal(fields.state, 'working');
  assert.match(fields.updated, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$/);
  assert.match(body, /^# Handover lu\.01\n\n## Lage\n\n## Offen\n\n## Regeln und Lehren\n$/);
});

test('aktualisiert Felder, Body bleibt byte-gleich, fremde Felder bleiben', () => {
  const home = setup();
  fs.mkdirSync(path.join(home, 'handover'));
  const body = '# Mein Body\n\nZeile ohne Umbruch am Ende';
  fs.writeFileSync(path.join(home, 'handover', 'lu.01.md'), `---\nsession: lu.01\nproject: alt\nextra: bleibt\ntask: alt\nstate: blocked\nupdated: 2020-01-01T00:00:00+00:00\n---\n${body}`);
  const r = run(home, ['neu']);
  assert.equal(r.status, 0, r.stderr);
  const { fields, body: b2 } = parseFrontmatter(read(home));
  assert.equal(fields.task, 'neu');
  assert.equal(fields.state, 'blocked', 'state ohne Argument bleibt');
  assert.equal(fields.project, 'alt', 'vorhandenes project bleibt');
  assert.equal(fields.extra, 'bleibt');
  assert.equal(b2, body);
});

test('--body ersetzt den Body, --archive legt Kopie ab', () => {
  const home = setup();
  run(home, ['erst']);
  const nb = path.join(home, 'neu.md');
  fs.writeFileSync(nb, '# Neu\n');
  const r = run(home, ['--archive', '--body', nb, 'Handover geschrieben', 'handover']);
  assert.equal(r.status, 0, r.stderr);
  const { fields, body } = parseFrontmatter(read(home));
  assert.equal(body, '# Neu\n');
  assert.equal(fields.state, 'handover');
  const arch = fs.readdirSync(path.join(home, 'handover', 'archive', 'lu.01'));
  assert.equal(arch.length, 1);
  assert.match(arch[0], /^\d{4}-\d\d-\d\dT\d\d-\d\d\.md$/);
  assert.match(fs.readFileSync(path.join(home, 'handover', 'archive', 'lu.01', arch[0]), 'utf8'), /task: erst/);
});

test('--no-create ohne Datei: nichts, Exit 0', () => {
  const home = setup();
  const r = run(home, ['--no-create', 'x']);
  assert.equal(r.status, 0);
  assert.equal(fs.existsSync(path.join(home, 'handover', 'lu.01.md')), false);
});

test('ohne Namen → Exit 1 mit Hinweis', () => {
  const home = setup();
  const r = run(home, ['x'], { CLAUDE_PID: '9999' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /claude -n/);
});

test('--name setzt fremde Datei; unbekannte Session → project leer', () => {
  const home = setup();
  const r = run(home, ['--name', 'or.02', 'fremd', 'done']);
  assert.equal(r.status, 0, r.stderr);
  const { fields } = parseFrontmatter(read(home, 'or.02'));
  assert.equal(fields.session, 'or.02');
  assert.equal(fields.project, '');
  assert.equal(fields.state, 'done');
});

test('Zeilenumbrüche im Task werden zu Leerzeichen, Backslashes bleiben', () => {
  const home = setup();
  run(home, ['a\nb \\n c']);
  assert.equal(parseFrontmatter(read(home)).fields.task, 'a b \\n c');
});
