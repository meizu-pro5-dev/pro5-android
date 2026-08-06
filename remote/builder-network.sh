#!/usr/bin/env bash

# Select the LineageOS endpoint used by Git's transparent URL rewrite.
configure_builder_lineage_source() {
  local source_name="${1:-direct}"
  local source_prefix

  case "$source_name" in
    cernet)
      # MirrorZ selects a currently healthy participating campus mirror and
      # redirects this stable path to its concrete LineageOS Git endpoint.
      source_prefix='https://mirrors.cernet.edu.cn/lineageOS/LineageOS/'
      ;;
    tuna)
      source_prefix='https://mirrors.tuna.tsinghua.edu.cn/git/lineageOS/LineageOS/'
      ;;
    direct)
      # A no-op rewrite overrides the mirror while keeping fixed config slots.
      source_prefix='https://github.com/LineageOS/'
      ;;
    *)
      printf 'Unsupported LineageOS source: %s\n' "$source_name" >&2
      return 2
      ;;
  esac

  export GIT_CONFIG_KEY_1="url.${source_prefix}.insteadOf"
  export GIT_CONFIG_VALUE_1=https://github.com/LineageOS/
}

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
      # As above, the no-op rewrite bypasses mirrors without shifting indices.
      mirror_prefix='https://android.googlesource.com/'
      ;;
    *)
      printf 'Unsupported AOSP source: %s\n' "$source_name" >&2
      return 2
      ;;
  esac

  export GIT_CONFIG_KEY_2="url.${mirror_prefix}.insteadOf"
  export GIT_CONFIG_VALUE_2=https://android.googlesource.com/
}

# Configure the builder's academic proxy, use mirrors for LineageOS/AOSP, and
# route only the Chinese mirrors directly. GitHub is substantially faster and
# more reliable through /etc/network_turbo on this builder.
configure_builder_network() {
  local direct_bypass
  local caller_shell_flags="$-"

  if [[ -r /etc/network_turbo ]]; then
    # The provider script is not nounset-safe. Temporarily relax nounset but
    # restore the caller's original state instead of changing every worker.
    set +u
    # shellcheck disable=SC1091
    source /etc/network_turbo >/dev/null 2>&1
    if [[ "$caller_shell_flags" == *u* ]]; then
      set -u
    else
      set +u
    fi
  fi

  direct_bypass='mirrors.cernet.edu.cn,.mirrors.cernet.edu.cn,mirrors.ustc.edu.cn,.mirrors.ustc.edu.cn,mirrors.bfsu.edu.cn,.mirrors.bfsu.edu.cn,mirrors.tuna.tsinghua.edu.cn,.mirrors.tuna.tsinghua.edu.cn'
  if [[ -n "${no_proxy:-}" ]]; then
    export no_proxy="${no_proxy},${direct_bypass}"
  else
    export no_proxy="$direct_bypass"
  fi
  export NO_PROXY="$no_proxy"

  # Keep manifest URLs unchanged for provenance. LineageOS defaults to GitHub
  # through the academic proxy; AOSP defaults to USTC. Both can be switched
  # per bounded attempt by the sync worker.
  export GIT_CONFIG_COUNT=3
  export GIT_CONFIG_KEY_0=http.version
  export GIT_CONFIG_VALUE_0=HTTP/1.1
  configure_builder_lineage_source "${PRO5_LINEAGE_SOURCE:-direct}"
  configure_builder_aosp_source "${PRO5_AOSP_SOURCE:-ustc}"

  # Bound zero-progress waits so repo can retry a failed project instead of
  # occupying the serial worker forever.
  export GIT_HTTP_LOW_SPEED_LIMIT=1024
  export GIT_HTTP_LOW_SPEED_TIME=60
}
