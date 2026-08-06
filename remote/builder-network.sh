#!/usr/bin/env bash

# Select the AOSP endpoint used by Git's transparent URL rewrite. Keeping the
# manifest URL untouched preserves provenance while allowing a failed mirror
# to be changed for one bounded repo-sync attempt.
configure_builder_aosp_source() {
  local source_name="${1:-ustc}"
  local mirror_prefix

  case "$source_name" in
    ustc)
      mirror_prefix='https://mirrors.ustc.edu.cn/aosp/'
      ;;
    bfsu)
      mirror_prefix='https://mirrors.bfsu.edu.cn/git/AOSP/'
      ;;
    tuna)
      mirror_prefix='https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/'
      ;;
    direct)
      export GIT_CONFIG_COUNT=2
      unset GIT_CONFIG_KEY_2 GIT_CONFIG_VALUE_2
      return
      ;;
    *)
      printf 'Unsupported AOSP source: %s\n' "$source_name" >&2
      return 2
      ;;
  esac

  export GIT_CONFIG_COUNT=3
  export GIT_CONFIG_KEY_2="url.${mirror_prefix}.insteadOf"
  export GIT_CONFIG_VALUE_2=https://android.googlesource.com/
}

# Configure the builder's academic proxy, use mirrors for LineageOS/AOSP, and
# route Chinese mirrors plus unmatched GitHub traffic directly.
configure_builder_network() {
  local direct_bypass

  if [[ -r /etc/network_turbo ]]; then
    set +u
    # shellcheck disable=SC1091
    source /etc/network_turbo >/dev/null 2>&1
    set -u
  fi

  direct_bypass='github.com,.github.com,githubusercontent.com,.githubusercontent.com,mirrors.ustc.edu.cn,.mirrors.ustc.edu.cn,mirrors.bfsu.edu.cn,.mirrors.bfsu.edu.cn,mirrors.tuna.tsinghua.edu.cn,.mirrors.tuna.tsinghua.edu.cn'
  if [[ -n "${no_proxy:-}" ]]; then
    export no_proxy="${no_proxy},${direct_bypass}"
  else
    export no_proxy="$direct_bypass"
  fi
  export NO_PROXY="$no_proxy"

  # Keep manifest URLs unchanged for provenance. LineageOS uses TUNA; AOSP
  # defaults to USTC and can be switched per attempt by the sync worker. Other
  # GitHub organizations continue to use the direct route.
  export GIT_CONFIG_COUNT=2
  export GIT_CONFIG_KEY_0=http.version
  export GIT_CONFIG_VALUE_0=HTTP/1.1
  export GIT_CONFIG_KEY_1=url.https://mirrors.tuna.tsinghua.edu.cn/git/lineageOS/LineageOS/.insteadOf
  export GIT_CONFIG_VALUE_1=https://github.com/LineageOS/
  configure_builder_aosp_source "${PRO5_AOSP_SOURCE:-ustc}"

  # Bound zero-progress waits so repo can retry a failed project instead of
  # occupying the serial worker forever.
  export GIT_HTTP_LOW_SPEED_LIMIT=1024
  export GIT_HTTP_LOW_SPEED_TIME=120
}
