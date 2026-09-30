'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { buildState } = require('./lib/state');

const NAME_RE = /^[A-Za-z0-9._-]+$/;
const INDEX = path.join(__dirname, 'public', 'index.html');

function send(res, status, type, body) {
  res.writeHead(status, { 'content-type': type, 'cache-control': 'no-store' });
  res.end(body);
}

function createServer({ claudeHome = path.join(os.homedir(), '.claude'), isAlive, devRoot } = {}) {
  return http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    try {
      if (url.pathname === '/') {
        return send(res, 200, 'text/html; charset=utf-8', fs.readFileSync(INDEX));
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
