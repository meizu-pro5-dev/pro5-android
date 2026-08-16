#!/usr/bin/env bash

set -euo pipefail

PRO5_BUILDER_HOST="${PRO5_BUILDER_HOST:-rom-builder}"
PRO5_BUILDER_PORT="${PRO5_BUILDER_PORT:-}"
PRO5_REMOTE_ROOT="${PRO5_REMOTE_ROOT:-/root/autodl-tmp/pro5-android10}"

if [[ -n "$PRO5_BUILDER_PORT" ]] && [[ ! "$PRO5_BUILDER_PORT" =~ ^[0-9]+$ ]]; then
  printf 'Invalid PRO5_BUILDER_PORT: %s\n' "$PRO5_BUILDER_PORT" >&2
  exit 2
fi

if [[ ! "$PRO5_REMOTE_ROOT" =~ ^/root/autodl-tmp/[A-Za-z0-9._/-]+$ ]] || \
    [[ "$PRO5_REMOTE_ROOT" == *'/../'* ]] || [[ "$PRO5_REMOTE_ROOT" == */.. ]]; then
  printf 'Refusing unsafe PRO5_REMOTE_ROOT: %s\n' "$PRO5_REMOTE_ROOT" >&2
  exit 2
fi

# The public tree ships no cloud endpoint. By default it uses the SSH alias
# `rom-builder` from the user's ~/.ssh/config; override with PRO5_BUILDER_HOST
# (user@host or alias) and PRO5_BUILDER_PORT when the alias does not carry one.
if [[ -n "$PRO5_BUILDER_PORT" ]]; then
  pro5_ssh=(
    ssh
    -p "$PRO5_BUILDER_PORT"
    -o BatchMode=yes
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=6
    "$PRO5_BUILDER_HOST"
  )
  pro5_rsync_ssh="ssh -p $PRO5_BUILDER_PORT -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
else
  pro5_ssh=(
    ssh
    -o BatchMode=yes
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=6
    "$PRO5_BUILDER_HOST"
  )
  pro5_rsync_ssh="ssh -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
fi
