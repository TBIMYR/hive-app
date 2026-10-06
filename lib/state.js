'use strict';
const path = require('node:path');
const os = require('node:os');
const { readRegistry, defaultIsAlive } = require('./registry');
const { readTailFollowingContinuation, parseTail } = require('./transcript');
const { readHandoverDir } = require('./handover');
const { projectFromCwd, groupKey, isPm, slugFromCwd, DEFAULT_DEV_ROOT } = require('./project');

const STALE_MS = 60 * 60 * 1000;
const MAX_TEXT = 600;

function clip(entry) {
  if (!entry) return null;
  const text = entry.text.length > MAX_TEXT ? entry.text.slice(0, MAX_TEXT) + '…' : entry.text;
  return { text, at: entry.at };
}

function taskOf(h, status, now) {
  if (!h || !h.task) return null;
  const updated = h.updatedAt ? Date.parse(h.updatedAt) : NaN;
  const stale = status === 'busy' && (Number.isNaN(updated) || now.getTime() - updated > STALE_MS);
  return { text: h.task, detail: h.detail || null, state: h.state, updatedAt: h.updatedAt, stale };
}

function buildState({
  claudeHome = path.join(os.homedir(), '.claude'),
  devRoot = DEFAULT_DEV_ROOT,
  now = new Date(),
  isAlive = defaultIsAlive,
} = {}) {
  const reg = readRegistry(path.join(claudeHome, 'sessions'), { isAlive });
  const handovers = readHandoverDir(path.join(claudeHome, 'handover'));
  const sessions = [];
  const seen = new Set();

  for (const e of reg.entries) {
    const h = handovers.get(e.name) || null;
    if (!e.alive && !h) continue;
    const errors = [];
    if (h && h.error) errors.push(`handover: ${h.error}`);
    let tail = { lastAssistant: null, lastUser: null, branch: null };
    if (e.sessionId && e.cwd) {
      try {
        const dir = path.join(claudeHome, 'projects', slugFromCwd(e.cwd));
        tail = parseTail(readTailFollowingContinuation(dir, e.sessionId));
      } catch (err) {
        errors.push(`transcript: ${err.message}`);
      }
    }
    const project = projectFromCwd(e.cwd, devRoot);
    const status = e.alive ? e.status : 'offline';
    sessions.push({
      name: e.name,
      project,
      group: groupKey(e.name, project),
      isPm: isPm(e.name),
      cwd: e.cwd,
      pid: e.pid,
      kind: e.kind,
      tmuxPane: e.tmuxPane,
      alive: e.alive,
      status,
      waitingFor: e.waitingFor,
      statusUpdatedAt: e.statusUpdatedAt,
      branch: tail.branch,
      lastAssistant: clip(tail.lastAssistant),
      lastUser: clip(tail.lastUser),
      task: taskOf(h, status, now),
      hasHandover: Boolean(h),
      errors,
    });
    seen.add(e.name);
  }

  for (const [name, h] of handovers) {
    if (seen.has(name)) continue;
    const project = h.project || '';
    sessions.push({
      name,
      project,
      group: groupKey(name, project),
      isPm: isPm(name),
      cwd: null,
      pid: null,
      kind: null,
      tmuxPane: null,
      alive: false,
      status: 'offline',
      waitingFor: null,
      statusUpdatedAt: null,
      branch: null,
      lastAssistant: null,
      lastUser: null,
      task: taskOf(h, 'offline', now),
      hasHandover: true,
      errors: h.error ? [`handover: ${h.error}`] : [],
    });
  }

  sessions.sort((a, b) =>
    a.group.localeCompare(b.group) ||
    (b.isPm - a.isPm) ||
    a.name.localeCompare(b.name));

  return { generatedAt: now.toISOString(), sessions, errors: reg.errors };
}

module.exports = { buildState, STALE_MS };
