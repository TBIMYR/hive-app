const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { parseFrontmatter, readHandoverDir } = require('../lib/handover');

const DIR = path.join(__dirname, 'fixtures', 'handover');
const BROKEN = path.join(__dirname, 'fixtures', 'handover-broken');

test('parseFrontmatter: fields and body', () => {
  const r = parseFrontmatter('---\na: 1\nb: x: y\n---\nbody\n');
  assert.deepEqual(r.fields, { a: '1', b: 'x: y' });
  assert.equal(r.body, 'body\n');
});

test('parseFrontmatter: no frontmatter → fields empty, everything is body', () => {
  const r = parseFrontmatter('# Body only\n');
  assert.deepEqual(r.fields, {});
  assert.equal(r.body, '# Body only\n');
});

test('parseFrontmatter: not closed → fields empty', () => {
  const r = parseFrontmatter('---\nsession: x\n');
  assert.deepEqual(r.fields, {});
});

test('readHandoverDir: map by name', () => {
  const m = readHandoverDir(DIR);
  const e = m.get('lu.01');
  assert.equal(e.task, 'Kalender-Ansicht Layout #41, PR offen');
  assert.equal(e.detail, 'grid done, list view next');
  assert.equal(e.state, 'working');
  assert.equal(e.updatedAt, '2026-09-30T16:09:00+02:00');
  assert.equal(e.project, 'lumen');
  assert.equal(m.has('archive'), false);
});

test('readHandoverDir: broken and frontmatter-less files → task null, no error', () => {
  const m = readHandoverDir(BROKEN);
  assert.equal(m.get('kaputt').task, null);
  assert.equal(m.get('nofm').task, null);
});

test('readHandoverDir: missing directory → empty map', () => {
  assert.equal(readHandoverDir('/nonexistent').size, 0);
});
