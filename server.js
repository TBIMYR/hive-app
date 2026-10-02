'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { buildState } = require('./lib/state');
const { readRegistry } = require('./lib/registry');
const { focusPid: defaultFocusPid } = require('./lib/focus');

const NAME_RE = /^[A-Za-z0-9._-]+$/;
const INDEX = path.join(__dirname, 'public', 'index.html');
const ICON_DIR = path.join(__dirname, 'public', 'icons');
// feste Liste statt Verzeichnis-Auslieferung; /apple-touch-icon.png und /favicon.ico fragen Browser von selbst ab
const ICONS = {
  '/icons/hive.svg': ['hive.svg', 'image/svg+xml'],
  '/icons/hive-512.png': ['hive-512.png', 'image/png'],
  '/icons/favicon-32.png': ['favicon-32.png', 'image/png'],
  '/apple-touch-icon.png': ['apple-touch-icon.png', 'image/png'],
  '/favicon.ico': ['favicon-32.png', 'image/png'],
};

function send(res, status, type, body) {
  res.writeHead(status, { 'content-type': type, 'cache-control': 'no-store' });
  res.end(body);
}

const json = (res, status, obj) => send(res, status, 'application/json; charset=utf-8', JSON.stringify(obj));

// Nur Anfragen ohne Origin (curl) oder von dieser Seite selbst; fremde Webseiten
// dürfen keine Fenster nach vorn holen.
function sameOrigin(req) {
  const o = req.headers.origin;
  if (!o) return true;
  try {
    const u = new URL(o);
    return (u.hostname === '127.0.0.1' || u.hostname === 'localhost') && u.host === req.headers.host;
  } catch { return false; }
}

async function handleFocus(req, res, pidStr, { claudeHome, isAlive, focusPid }) {
  if (req.method !== 'POST') return send(res, 405, 'text/plain', 'POST only');
  if (!sameOrigin(req)) return send(res, 403, 'text/plain', 'forbidden');
  if (!/^\d+$/.test(pidStr)) return send(res, 400, 'text/plain', 'bad pid');
  const pid = Number(pidStr);
  const entry = readRegistry(path.join(claudeHome, 'sessions'), isAlive ? { isAlive } : undefined)
    .entries.find(e => e.pid === pid && e.alive);
  if (!entry) return json(res, 404, { ok: false, reason: 'keine laufende Session mit dieser PID' });
  if (entry.kind === 'bg') return json(res, 409, { ok: false, reason: 'Hintergrund-Session ohne Fenster' });
  const r = await focusPid(pid);
  return json(res, r.ok ? 200 : 422, r);
}

function createServer({ claudeHome = path.join(os.homedir(), '.claude'), isAlive, devRoot, focusPid = defaultFocusPid } = {}) {
  return http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    try {
      if (url.pathname.startsWith('/api/focus/')) {
        return await handleFocus(req, res, url.pathname.slice('/api/focus/'.length), { claudeHome, isAlive, focusPid });
      }
      if (url.pathname === '/') {
        // Diagnose: wer öffnet die Seite wann (landet in /tmp/hive.log)
        console.log(`${new Date().toISOString()} GET / ua="${req.headers['user-agent'] || ''}" referer="${req.headers.referer || ''}"`);
        return send(res, 200, 'text/html; charset=utf-8', fs.readFileSync(INDEX));
      }
      if (ICONS[url.pathname]) {
        const [file, type] = ICONS[url.pathname];
        return send(res, 200, type, fs.readFileSync(path.join(ICON_DIR, file)));
      }
      if (url.pathname === '/api/state') {
        const state = buildState({ claudeHome, isAlive, devRoot });
        return send(res, 200, 'application/json; charset=utf-8', JSON.stringify(state));
      }
      if (url.pathname.startsWith('/api/handover/')) {
        const name = decodeURIComponent(url.pathname.slice('/api/handover/'.length));
        if (!NAME_RE.test(name) || name.includes('..')) return send(res, 400, 'text/plain', 'bad name');
        const file = path.join(claudeHome, 'handover', `${name}.md`);
        if (!fs.existsSync(file)) return send(res, 404, 'text/plain', 'no handover');
        return send(res, 200, 'text/markdown; charset=utf-8', fs.readFileSync(file));
      }
      return send(res, 404, 'text/plain', 'not found');
    } catch (err) {
      return send(res, 500, 'text/plain', err.message);
    }
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT) || 7777;
  createServer().listen(port, '127.0.0.1', () => {
    console.log(`hive: http://127.0.0.1:${port}`);
  });
}

module.exports = { createServer };
