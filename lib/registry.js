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

// "keeper.01:@13.%13" → "%13". Die Pane-ID bleibt, wenn Session oder tmux umbenannt werden.
function paneOf(tmux) {
  const m = typeof tmux === 'string' ? tmux.match(/%\d+$/) : null;
  return m ? m[0] : null;
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
      // Vorrats-Prozess von Claude Code für die nächste Hintergrund-Session, noch keine Session
      if (j.spare === true) continue;
      entries.push({
        pid: j.pid,
        name: typeof j.name === 'string' && j.name ? j.name : `pid-${j.pid}`,
        cwd: j.cwd || '',
        sessionId: j.sessionId || null,
        status: j.status || 'unknown',
        waitingFor: j.waitingFor || null,
        kind: j.kind || null,
        tmuxPane: paneOf(j.tmux),
        startedAt: typeof j.startedAt === 'number' ? j.startedAt : 0,
        statusUpdatedAt: toIso(j.statusUpdatedAt ?? j.updatedAt),
        alive: isAlive(j.pid),
        jobId: j.jobId || null,
        parkedJobId: j.parkedJobId || null,
      });
    } catch (err) {
      errors.push(`${f}: ${err.message}`);
    }
  }
  // Hat ein Fenster sein Gespräch an eine Hintergrund-Session übergeben (parkedJobId), läuft die
  // Arbeit dort und das Fenster zeigt sie nur an: eine Session mit dem Status von dort.
  const jobs = new Map(entries.filter(e => e.alive && e.jobId).map(e => [e.jobId, e]));
  const parked = new Set();
  for (const e of entries) {
    const job = e.alive && e.parkedJobId ? jobs.get(e.parkedJobId) : null;
    if (!job || job === e) continue;
    Object.assign(e, { status: job.status, waitingFor: job.waitingFor, statusUpdatedAt: job.statusUpdatedAt });
    parked.add(job);
  }
  for (let i = entries.length - 1; i >= 0; i--) {
    if (parked.has(entries[i])) entries.splice(i, 1);
    else { delete entries[i].jobId; delete entries[i].parkedJobId; }
  }
  // Duplikate unter lebenden Einträgen: den Namen behält zuerst eine Session mit
  // Fenster (kind != "bg"), danach die jüngste; alle anderen bekommen #pid.
  // Hintergrund-Sessions laufen ohne Fenster und wären sonst nicht auffindbar.
  const byName = new Map();
  for (const e of entries) {
    if (!e.alive) continue;
    if (!byName.has(e.name)) byName.set(e.name, []);
    byName.get(e.name).push(e);
  }
  const isBg = e => (e.kind === 'bg' ? 1 : 0);
  for (const list of byName.values()) {
    if (list.length < 2) continue;
    list.sort((a, b) => isBg(a) - isBg(b) || b.startedAt - a.startedAt);
    for (const e of list.slice(1)) e.name = `${e.name}#${e.pid}`;
  }
  return { entries, errors };
}

module.exports = { readRegistry, defaultIsAlive };
