#!/bin/busybox sh
# /etc/opt/gatus/runner.sh
# Ref:
# https://stackoverflow.com/questions/360201/how-do-i-kill-background-processes-jobs-when-my-shell-script-exits
# https://github.com/TwiN/gatus/blob/master/Dockerfile

set -eu

echo "Started Gatus runner script"

/authelia_login.sh &
/gatus &

# shellcheck disable=SC2064
trap "trap - TERM && kill -- -$$" INT TERM EXIT

for job in $(jobs -p); do
  wait "$job"
done
