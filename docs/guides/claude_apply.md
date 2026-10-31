# Claude Code: assisted apply sessions

Work through a list of commands, such as `notes/apply.md`, with Claude Code watching and
preparing each next step. You type and run every command; Claude only reads what your terminal
showed.

- `script` records your terminal to `notes/session.log` (gitignored, like the rest of `notes/`)
- Claude runs `tools/wait_prompt.sh` in the background. It returns when your command has finished
  and the shell is back at a prompt, with that command's output.
- Claude checks the output against the expected result, then `tools/apply_next.sh` puts the next
  command on your clipboard, posts a notification and speaks one sentence on what the step does

## Safety

- The session's only input is your keyboard. The log is a copy of what the terminal displayed,
  so this design gives Claude no path to type into it. Claude is not allowed `ssh`, `tmux` or
  `osascript`; the permission rules, not the design, are what keep it that way.
- What the terminal shows is untrusted: a host's output could try to steer Claude. You read each
  clipboard command before pressing Enter; that is the control.
- `notes/session.log` holds whatever your terminal displayed. Exit `script` before a step that
  prints a secret (`age -d`, `cat` of a secrets file, a password export) and rerun it afterwards;
  `-a` appends.
- Keep Claude in Chrome (`/chrome`) off during a session: it would act in your logged-in tabs
- Each clipboard command is one line of printable text with no trailing newline, so pasting it
  doesn't run it. Read it before pressing Enter. The clipboard is overwritten every step.

## 1. Start

From the repo root:

```bash
script -q -a -F notes/session.log zsh -f -o interactivecomments
```

`zsh -f` skips your rc files, so the prompt ends in `%` and a space, which the watcher
recognises; the powerlevel10k prompt ends in `❯` and would never wake it. `interactivecomments`
brings back the `# note` lines (section 3) that your rc files would otherwise enable. `ssh` and `tools/*.sh`
work as usual, interactive sessions included. Then `/apply notes/apply.md Full backup` in Claude
Code to start at that heading, or `/apply notes/apply.md` for the whole file.

## 2. The loop (Claude)

`/apply FILE [HEADING]` (`.claude/skills/apply/SKILL.md`) is Claude's side: it reads the file into
a step list, arms `tools/wait_prompt.sh`, checks each result against the step's expected
output, and stages the next command with `tools/apply_next.sh`. Claude never runs a step's
commands itself, and says so in the notification before any step that prints a secret, so you
can exit `script` first.

## 3. Human steps and notes

A browser check, a test from the phone or anything else off the terminal works the same way: the
notification says what to do and what to look for, and the clipboard holds its URL or command.
Report back by typing a comment at the prompt, which both bash and zsh accept:

```bash
# phone: curl got 403, ClientHost is the mobile IP
# vault SSO ok from the extension; the app asks for 2FA twice
# screenshot ~/Desktop/grafana.png
```

Enter brings back the prompt, so Claude wakes with the note. Claude can read a screenshot by path.

## 4. Long waits

`tools/wait_prompt.sh` has no timeout: a command that sleeps, pulls an image or waits on a
service holds it until the prompt returns. For a wait with no command, such as "within 15 min it's
transcribed", either run `sleep 900` in the session or ask Claude to start a background timer
and notify you when it's up.

A command whose output pauses for 2 s on a line ending in `$`, `#` or `%` and a space wakes Claude
early; it sees the command still running and re-arms.

## 5. Finish

Exit `script` (`exit` or Ctrl-D), then delete the log: `rm notes/session.log`
