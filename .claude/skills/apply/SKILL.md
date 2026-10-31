---
name: apply
description: Walk the human through a command list (notes/apply.md or any md file) in a recorded terminal, one step at a time
disable-model-invocation: true
allowed-tools:
  - Bash(tools/wait_prompt.sh)
  - Bash(tools/wait_prompt.sh *)
  - Bash(tools/apply_next.sh *)
  - Bash(touch notes/session.log)
  - Read
---

# /apply FILE [HEADING]

Assisted apply session: the human types and runs every command in a shell recorded by `script`;
you read the recording, check each result and stage the next command. The human side and the
safety model are in `docs/guides/claude_apply.md`; this is your side.

`$ARGUMENTS`: the markdown file, then the rest is HEADING, free text naming the heading to start
at ("4", "Full backup", "Headscale ACLs"). Start at the first heading in the file that contains
it, case-insensitive, and run to the end of the file. With no HEADING, begin at the first step.

## 1. Build the step list

Read FILE. A step is one of:

- a command line inside a fenced block, run from where the block's `# On ...` / `# From ...`
  comment says. A `\`-continued command is one step, joined with spaces.
- a `# ...` comment that asks for a human action (browser, phone, console) or states an expected
  result: these are checks, attached to the command before them or staged as human steps
- prose between blocks: context and rollback notes, which you keep in mind, not stage

Print the list from HEADING onwards as a numbered table (step, where, command) in the
chat before staging anything, so the human can correct it with a `# note`.

## 2. Open the session

If `notes/session.log` is missing: `touch notes/session.log`, then stage the guide's start
command with `tools/apply_next.sh` and go to step 3. The first wake is the plain `%` prompt.

## 3. The loop

1. Arm `tools/wait_prompt.sh` with `run_in_background` and stop your turn. Its notification
   wakes you with the output since the last wake.
2. Read the output with these checks, in order:
   - **Echo**: the command line the shell echoed is the one you staged, arguments included. A
     missing argument or a joined paste is a wrong step: re-stage it and say what differed.
   - **Note**: a `# ...` line is the human talking. Answer it before anything else.
   - **Result**: compare with the step's expected result and the exit signs in the output.
3. Stage the next step with `tools/apply_next.sh TEXT MESSAGE`:
   - TEXT: the command, the URL of a human step, or `''`
   - MESSAGE: one line, verdict then next step: "secsvcs failed_units clean → 1c:
     install_crowdsec secsvcs"
   - a failed step: TEXT is the diagnostic command, MESSAGE names the failure. The step stays
     current until the human's note or the diagnostic clears it.
   - a secret-printing step (`age -d`, a secrets file, a password export): MESSAGE says "exit
     script first", TEXT is `''`, and the step is staged after the human's note that they're back
   - a wait with no command ("within 15 min"): MESSAGE says how long and what to look for; the
     human runs `sleep` or notes when it's done
   - more than one line to explain: TEXT `''`, MESSAGE "see Claude terminal", explanation in your
     reply. End that reply on what to do, not on a question only the chat can answer.
4. Write one line in the chat: step done, verdict, what was staged. Go to 1.

Every step's commands run only in the recorded session. The clipboard holds one line of printable
text, so a step with several commands is several stages.

## 4. Finish

The session ends when the last step's result is checked or the human notes `# stop`. Then stage
`''` with MESSAGE "done: exit script, rm notes/session.log" and summarise in the chat: steps
applied, failures and their state, checks the human still owes.
