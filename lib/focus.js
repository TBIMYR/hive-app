'use strict';
// Brings a session's iTerm window and tab to the front.
// Path: PID → terminal (ps) → iTerm session with this tty (AppleScript).
const { execFile } = require('node:child_process');

const SCRIPT = `
on run argv
  set target to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if tty of s is target then
            tell w to select
            tell t to select
            tell s to select
            activate
            return "ok"
          end if
        end repeat
      end repeat
    end repeat
  end tell
  return "notfound"
end run`;

function run(cmd, args, timeout = 5000) {
  return new Promise(resolve => {
    execFile(cmd, args, { timeout }, (err, stdout, stderr) => {
      resolve({ err, out: String(stdout || '').trim(), errOut: String(stderr || '').trim() });
    });
  });
}

async function ttyOf(pid) {
  const r = await run('ps', ['-o', 'tty=', '-p', String(pid)]);
  const tty = r.out;
  if (r.err || !tty || tty === '??') return null;
  return tty.startsWith('/dev/') ? tty : `/dev/${tty}`;
}

async function focusPid(pid) {
  const tty = await ttyOf(pid);
  if (!tty) return { ok: false, reason: 'session has no terminal' };
  const r = await run('osascript', ['-e', SCRIPT, tty]);
  if (r.err) return { ok: false, reason: r.errOut || r.err.message };
  if (r.out !== 'ok') return { ok: false, reason: `no iTerm tab for ${tty}` };
  return { ok: true, tty };
}

module.exports = { focusPid, ttyOf };
