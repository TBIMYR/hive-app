---
name: handover
description: Writes this session's handover to ~/.claude/handover/<name>.md so that a successor session with the same name reads it at startup. Invoke before every planned end or restart, or when the user says /handover.
---

1. Use `Write` to put the handover text into a file in the scratchpad (e.g. `<scratchpad>/handover.md`). Keep the three section headings exactly as shown. Structure:

       # Handover <name> — as of <date>

       ## Situation
       Repo state, branches, what is merged/pushed, running servers. Measured, not assumed.

       ## Open
       First line: what the successor should do first. Then what is missing, who has to decide,
       which permissions are missing. With ticket/PR numbers.

       ## Rules and lessons
       What was added or went wrong in this session that the successor needs to know.

   If the project still has an old handoff file in the previous format (e.g. `HANDOFF-<name>.md` or `handoff/<date>/…`), point to its path once in the "Situation" section.

2. Run exactly one Bash call:

       ~/.claude/bin/cc-task --archive --body <scratchpad>/handover.md --detail "<what the successor should do first, at most 120 characters>" "<topic, at most 4 words / 40 characters>" handover

   This archives the previous version and writes frontmatter and body in one step.

3. Confirm to the user in one sentence, with the path `~/.claude/handover/<name>.md`.

Never touch the handover file directly with `Write` or `Edit`; `cc-task` is the only writer.
