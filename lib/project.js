'use strict';
const path = require('node:path');
const os = require('node:os');

const DEFAULT_DEV_ROOT = path.join(os.homedir(), 'Development');

function projectFromCwd(cwd, devRoot = DEFAULT_DEV_ROOT) {
  if (!cwd) return '';
  const rel = path.relative(devRoot, cwd);
  if (rel && !rel.startsWith('..') && !path.isAbsolute(rel)) {
    return rel.split(path.sep)[0];
  }
  return path.basename(cwd);
}

function groupKey(name, project) {
  const i = name.indexOf('.');
  return i > 0 ? name.slice(0, i) : project;
}

function isPm(name) {
  return /\.pm$/.test(name);
}

function slugFromCwd(cwd) {
  return String(cwd).replace(/[^A-Za-z0-9]/g, '-');
}

module.exports = { projectFromCwd, groupKey, isPm, slugFromCwd, DEFAULT_DEV_ROOT };
