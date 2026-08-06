#!/usr/bin/env bash

# Configure the builder's academic proxy, use TUNA for LineageOS/AOSP, and
# route the Chinese mirror plus unmatched GitHub traffic directly.
configure_builder_network() {
  local direct_bypass

  if [[ -r /etc/network_turbo ]]; then
    set +u
    # shellcheck disable=SC1091
    source /etc/network_turbo >/dev/null 2>&1
    set -u
  fi

  direct_bypass='github.com,.github.com,githubusercontent.com,.githubusercontent.com,mirrors.tuna.tsinghua.edu.cn,.mirrors.tuna.tsinghua.edu.cn'
  if [[ -n "${no_proxy:-}" ]]; then
    export no_proxy="${no_proxy},${direct_bypass}"
  else
    export no_proxy="$direct_bypass"
  fi
  export NO_PROXY="$no_proxy"

  # Keep manifest URLs unchanged for provenance while transparently fetching
  # LineageOS and AOSP objects from TUNA. Other GitHub organizations continue
  # to use the direct route.
  export GIT_CONFIG_COUNT=3
  export GIT_CONFIG_KEY_0=http.version
  export GIT_CONFIG_VALUE_0=HTTP/1.1
  export GIT_CONFIG_KEY_1=url.https://mirrors.tuna.tsinghua.edu.cn/git/lineageOS/LineageOS/.insteadOf
  export GIT_CONFIG_VALUE_1=https://github.com/LineageOS/
  export GIT_CONFIG_KEY_2=url.https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/.insteadOf
  export GIT_CONFIG_VALUE_2=https://android.googlesource.com/

  # Bound zero-progress waits so repo can retry a failed project instead of
  # occupying the serial worker forever.
  export GIT_HTTP_LOW_SPEED_LIMIT=1024
  export GIT_HTTP_LOW_SPEED_TIME=120
}
