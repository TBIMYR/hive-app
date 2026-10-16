# Session status

- Always start sessions with `claude -n <name>` (e.g. `lu.pm`, `lu.01`); the name is the key for the dashboard and the handover.
- Set the task line yourself when you take on a task, when you are blocked and when you are done: `~/.claude/bin/cc-task "<topic>" <working|blocked|waiting|done>` directly via Bash, NOT via the `/status` skill. Send the call in parallel in the same step as a tool call that is due anyway (e.g. with the first Read/Bash of a task or with the last action before), so that no extra model request is needed.
- The task line names only the topic, at most 4 words / 40 characters, without ticket numbers and without steps (e.g. "Android app", "New iPhone build"). The dashboard shows the state anyway. `cc-task` rejects longer lines.
- More context optionally as a subline: `cc-task --detail "<one line, at most 120 characters>" "<topic>" <state>`, e.g. what exactly is running or what exactly you are waiting for. Every call replaces it; without `--detail` it is empty.
- `blocked` only when the session cannot go on without a decision or approval from me. If your own work is done and only a reply is missing (from me, Kim, another session), then `waiting`, naming in brackets whom you are waiting for (e.g. "Release (lu.pm)").
- Notes: when I say "put that in the notes" or "on a sticky note" (e.g. instructions that would otherwise get lost in the history), store the text with `~/.claude/bin/cc-note "<text>"` (Markdown, multiple lines allowed; long text via stdin). It is appended to the bottom of the session's notepad; Hive shows it under "Notes" (⌘T). Only on request, not on your own.
- When to write a handover + `/clear`, when to keep going (every request sends the whole history; after a longer break the cache has to be written again; a long history lowers the quality):
  - Handover + `/clear`: the next task is independent (another ticket), the session will probably sit idle for a long time, or the history is already very large.
  - Keep going: a follow-up question or fix for the task just finished, follow-up work on the same topic.
  - PM sessions keep running, but update their handover regularly and are only cleared when the topic changes.
  - Middle ground: `/compact` when the session should keep working but the history gets too long. It does not survive a restart, the handover does.
- Instead of `/clear`, a session may also be closed and started again; what matters is the same name.
- PM ↔ worker flow:
  1. The PM hands out a task with `~/.claude/bin/cc-spawn <name> <directory> "<task>"` (new tab, loads the handover for the name, refuses names that are running).
     Free names first: before a new name (e.g. `lu.05`), reuse an existing offline session of the project with a handover (`lu.01` …); `cc-spawn` loads its handover. New numbers only when all existing ones are running.
  2. The worker is done: write the handover, `cc-task … done` (or `waiting`), then tell its PM briefly via SendMessage what is done. The message wakes the PM; nobody has to poll.
  3. The PM decides: follow-up work on the same topic → SendMessage to the worker, it keeps running. A new, independent ticket or nothing left to do → `~/.claude/bin/cc-close <name>` (types `/exit`, closes the tab; refuses while the worker is working or has no handover) and, if needed, a new one via `cc-spawn`.
  4. In a new directory (fresh worktree) Claude Code asks once for trust; I confirm that myself. Real decisions stay `blocked`.
- `/handover` before every planned end or restart. The successor session with the same name reads it automatically at startup.
- The PM session may read the workers' `~/.claude/handover/<name>.md` at any time instead of asking them.
