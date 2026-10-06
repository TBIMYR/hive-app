'use strict';

// Splits a handover file into frontmatter fields and body (same rules as HiveCore's parser).
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

module.exports = { parseFrontmatter };
