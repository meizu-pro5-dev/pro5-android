#!/usr/bin/env bash

# Configure the builder's academic proxy while routing GitHub directly. The
# proxy is necessary for Google-hosted Android sources, but long GitHub
# transfers are substantially faster and more reliable without it.
configure_builder_network() {
  local github_bypass

  if [[ -r /etc/network_turbo ]]; then
    set +u
    # shellcheck disable=SC1091
    source /etc/network_turbo >/dev/null 2>&1
    set -u
  fi

  github_bypass='github.com,.github.com,githubusercontent.com,.githubusercontent.com'
  if [[ -n "${no_proxy:-}" ]]; then
    export no_proxy="${no_proxy},${github_bypass}"
  else
    export no_proxy="$github_bypass"
  fi
  export NO_PROXY="$no_proxy"

  # GitHub's HTTP/2 path has produced silent long-lived stalls on this host.
  # Force Git's libcurl transport to HTTP/1.1 and bound zero-progress waits so
  # repo can retry a failed project instead of occupying a worker forever.
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=http.version
  export GIT_CONFIG_VALUE_0=HTTP/1.1
  export GIT_HTTP_LOW_SPEED_LIMIT=1024
  export GIT_HTTP_LOW_SPEED_TIME=120
}
