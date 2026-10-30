#!/bin/bash
# Hands the human the next step of a Claude-assisted session (docs/guides/claude_apply.md):
# copies TEXT (a command or a URL) to the clipboard, shows MESSAGE as a notification and
# speaks a short cue. Claude is allowed this script rather than osascript, which can drive
# any app.
# Usage:
#   tools/apply_next.sh TEXT MESSAGE
#   tools/apply_next.sh '' MESSAGE    # nothing to paste; the clipboard is left alone

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

text=$1
msg=${2:?usage: $0 TEXT MESSAGE}
# A pasted newline or carriage return would run the command before the human has read it
[[ $text != *[[:cntrl:]]* ]] || die "TEXT must be one line of printable text"

if [[ -n $text ]]; then printf '%s' "$text" | pbcopy; fi
# The message goes in as an argument, never spliced into the script, so quotes in it are inert
osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "homelab"' \
  -e 'end run' "$msg"
say "next step"
