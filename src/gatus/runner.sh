#!/usr/bin/env bash
# /etc/opt/gatus/runner.sh
# Ref:
# https://stackoverflow.com/questions/360201/how-do-i-kill-background-processes-jobs-when-my-shell-script-exits
# https://github.com/TwiN/gatus/blob/master/Dockerfile

set -euo pipefail

/authelia_login.sh &
/gatus &

# shellcheck disable=SC2064
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

wait < <(jobs -p)
