#!/usr/bin/env bash

set -euo pipefail
finish=0
trap 'finish=1' SIGTERM
trap 'finish=1' SIGINT

tag=$(date -Ins)

while (( finish != 1 ))
do
  echo "$tag"
  sleep 10
done
