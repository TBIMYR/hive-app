---
name: status
description: Sets this session's task line for the session dashboard. Only when the user explicitly invokes /status. For automatic updates, call cc-task directly via Bash (rule in the global CLAUDE.md), not this skill.
---

Run exactly one Bash call, nothing else:

    ~/.claude/bin/cc-task "<topic only, at most 4 words / 40 characters, e.g. \"Android app\">" <state>

`state` is `working` (task in progress), `blocked` (cannot continue without a decision or approval from the user), `waiting` (own work done, only waiting for feedback from a person or another session; name who in brackets, e.g. "Release (lu.pm)") or `done` (task finished, waiting for the next one).

If a text was passed as an argument, use it unchanged; if `cc-task` rejects it as too long, shorten it to the topic. No follow-up questions, no explanation, no output other than a one-line confirmation.

If the script reports that the session name is unknown, tell the user in one sentence that the session has to be started with `claude -n <name>`, and carry on.
