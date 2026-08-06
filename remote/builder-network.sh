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
}
