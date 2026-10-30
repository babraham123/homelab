#!/bin/bash
# Blocks until a recorded shell session (docs/guides/claude_apply.md) has new output and is
# back at a prompt, then prints that output with terminal escapes stripped. Claude runs it in
# the background, so it's woken once per finished command instead of polling the log.
# A prompt is a last line ending in "$ ", "# " or "% " (remote bash, root, local zsh) after
# 2 s without output. A pause while typing, a long sleep, sudo's password prompt or a progress
# line like "45%" doesn't match, so the wait lasts as long as the command does.
# Usage:
#   tools/wait_prompt.sh [LOG]    # default notes/session.log

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."
log=${1:-notes/session.log}
[[ -f $log ]] || die "no ${log}: start the session with script -q -a -F ${log} zsh -f -o interactivecomments"

# CSI and OSC sequences, then each line's text after its last carriage return (zsh's
# PROMPT_SP filler, progress bars redrawing), then characters erased by a backspace
clean() {
  perl -pe '
    s/\e\[[0-?]*[ -\/]*[@-~]//g; s/\e\][^\a\e]*(?:\a|\e\\)//g; s/\e[()=>][0-9A-Za-z]?//g;
    s/\r+\n/\n/g; s/[^\n]*\r//g; 1 while s/[^\x08]\x08//;
  '
}

size_of() { stat -f %z "$log"; }
start=$(size_of)
last=$start
quiet=0
while sleep 0.5; do
  size=$(size_of)
  if (( size < start )); then start=0; fi    # the log was truncated
  if (( size != last )); then last=$size quiet=0; continue; fi
  if (( size == start || ++quiet < 4 )); then continue; fi
  line=$(tail -c 400 "$log" | clean | awk 'NF { l = $0 } END { printf "%s", l }')
  if [[ $line =~ [\$#%]\ $ ]]; then
    output=$(tail -c "+$((start + 1))" "$log" | clean)
    lines=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
    if (( lines > 200 )); then echo "(first $((lines - 200)) of ${lines} lines dropped; see ${log})"; fi
    printf '%s\n' "$output" | tail -n 200
    exit 0
  fi
done
