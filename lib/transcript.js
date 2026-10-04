'use strict';
const fs = require('node:fs');

const DEFAULT_TAIL_BYTES = 64 * 1024;

function readTail(file, bytes = DEFAULT_TAIL_BYTES) {
  let fd;
  try {
    fd = fs.openSync(file, 'r');
    const size = fs.fstatSync(fd).size;
    const len = Math.min(bytes, size);
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, size - len);
    let text = buf.toString('utf8');
    if (len < size) {
      // Discard the first (possibly truncated) line
      const nl = text.indexOf('\n');
      text = nl >= 0 ? text.slice(nl + 1) : '';
    }
    return text;
  } catch {
    return '';
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

function textOf(content) {
  if (typeof content === 'string') return content.trim();
  if (Array.isArray(content)) {
    return content
      .filter(b => b && b.type === 'text' && typeof b.text === 'string')
      .map(b => b.text)
      .join('\n')
      .trim();
  }
  return '';
}

function parseTail(text) {
  const lines = text.split('\n');
  let lastAssistant = null;
  let lastUser = null;
  let branch = null;
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i].trim();
    if (!line) continue;
    let obj;
    try {
      obj = JSON.parse(line);
    } catch {
      continue;
    }
    if (branch === null && typeof obj.gitBranch === 'string') branch = obj.gitBranch;
    const content = obj.message && obj.message.content;
    if (!lastAssistant && obj.type === 'assistant') {
      const t = textOf(content);
      if (t) lastAssistant = { text: t, at: obj.timestamp || null };
    } else if (!lastUser && obj.type === 'user' && !obj.isMeta) {
      const t = textOf(content);
      if (t && !t.startsWith('<')) lastUser = { text: t, at: obj.timestamp || null };
    }
    if (lastAssistant && lastUser && branch !== null) break;
  }
  return { lastAssistant, lastUser, branch };
}

module.exports = { readTail, parseTail, DEFAULT_TAIL_BYTES };
