'use strict';
const fs = require('node:fs');
const path = require('node:path');

function parseFrontmatter(text) {
  const lines = text.split('\n');
  if (lines[0] !== '---') return { fields: {}, body: text };
  let end = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i] === '---') { end = i; break; }
  }
  if (end < 0) return { fields: {}, body: text };
  const fields = {};
  for (const line of lines.slice(1, end)) {
    const m = /^([A-Za-z_][\w-]*):\s?(.*)$/.exec(line);
    if (m) fields[m[1]] = m[2];
  }
  return { fields, body: lines.slice(end + 1).join('\n') };
}

function readHandoverDir(dir) {
  const map = new Map();
  let files = [];
  try {
    files = fs.readdirSync(dir).filter(f => f.endsWith('.md'));
  } catch {
    return map;
  }
  for (const f of files) {
    const name = f.slice(0, -3);
    const entry = { name, task: null, detail: null, state: null, updatedAt: null, project: null, error: null };
    try {
      const { fields } = parseFrontmatter(fs.readFileSync(path.join(dir, f), 'utf8'));
      entry.task = fields.task || null;
      entry.detail = fields.detail || null;
      entry.state = fields.state || null;
      entry.updatedAt = fields.updated || null;
      entry.project = fields.project || null;
    } catch (err) {
      entry.error = err.message;
    }
    map.set(name, entry);
  }
  return map;
}

module.exports = { parseFrontmatter, readHandoverDir };
