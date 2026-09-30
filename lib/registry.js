'use strict';
const fs = require('node:fs');
const path = require('node:path');

function defaultIsAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code === 'EPERM';
  }
}

function toIso(ms) {
  return typeof ms === 'number' ? new Date(ms).toISOString() : null;
}

function readRegistry(dir, { isAlive = defaultIsAlive } = {}) {
  const entries = [];
  const errors = [];
  let files = [];
  try {
    files = fs.readdirSync(dir).filter(f => f.endsWith('.json'));
  } catch {
    return { entries, errors };
  }
  for (const f of files) {
    const file = path.join(dir, f);
    try {
      const j = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (typeof j.pid !== 'number') continue;
      entries.push({
        pid: j.pid,
        name: typeof j.name === 'string' && j.name ? j.name : `pid-${j.pid}`,
        cwd: j.cwd || '',
        sessionId: j.sessionId || null,
        status: j.status || 'unknown',
        waitingFor: j.waitingFor || null,
        startedAt: typeof j.startedAt === 'number' ? j.startedAt : 0,
        statusUpdatedAt: toIso(j.statusUpdatedAt ?? j.updatedAt),
        alive: isAlive(j.pid),
      });
    } catch (err) {
      errors.push(`${f}: ${err.message}`);
    }
  }
  // Duplikate: jüngstes startedAt behält den Namen, andere bekommen #pid
  const byName = new Map();
  for (const e of entries) {
    if (!byName.has(e.name)) byName.set(e.name, []);
    byName.get(e.name).push(e);
  }
  for (const list of byName.values()) {
    if (list.length < 2) continue;
    list.sort((a, b) => b.startedAt - a.startedAt);
    for (const e of list.slice(1)) e.name = `${e.name}#${e.pid}`;
  }
  return { entries, errors };
}

module.exports = { readRegistry, defaultIsAlive };
