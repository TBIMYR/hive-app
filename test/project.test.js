const test = require('node:test');
const assert = require('node:assert/strict');
const { projectFromCwd, groupKey, isPm, slugFromCwd } = require('../lib/project');

const DEV = '/Users/dev/Development';

test('projectFromCwd: erster Pfadteil unter Development', () => {
  assert.equal(projectFromCwd(`${DEV}/fjord/fjord-app`, DEV), 'fjord');
  assert.equal(projectFromCwd(`${DEV}/lumen/worktrees/foo`, DEV), 'lumen');
  assert.equal(projectFromCwd(`${DEV}/hive`, DEV), 'hive');
});

test('projectFromCwd: außerhalb Development → basename', () => {
  assert.equal(projectFromCwd('/Users/dev', DEV), 'dev');
  assert.equal(projectFromCwd('', DEV), '');
});

test('groupKey: Präfix vor dem Punkt, sonst project', () => {
  assert.equal(groupKey('lu.pm', 'lumen'), 'lu');
  assert.equal(groupKey('fj.02', 'fjord'), 'fj');
  assert.equal(groupKey('hive-01', 'hive'), 'hive');
});

test('isPm', () => {
  assert.equal(isPm('lu.pm'), true);
  assert.equal(isPm('lu.01'), false);
  assert.equal(isPm('relay-d3'), false);
});

test('slugFromCwd: alles außer alphanumerisch wird -', () => {
  assert.equal(slugFromCwd(`${DEV}/fjord/fjord-app`), '-Users-dev-Development-fjord-fjord-app');
  assert.equal(slugFromCwd('/a b/c.d@e'), '-a-b-c-d-e');
});
