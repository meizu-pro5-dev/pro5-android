#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

"${pro5_ssh[@]}" bash -s -- "$PRO5_REMOTE_ROOT" <<'REMOTE'
set -euo pipefail

remote_root="$1"

if [[ -r /etc/network_turbo ]]; then
  set +u
  # shellcheck disable=SC1091
  source /etc/network_turbo >/dev/null 2>&1
  set -u
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  bc \
  bison \
  build-essential \
  ccache \
  curl \
  device-tree-compiler \
  flex \
  g++-multilib \
  gcc-multilib \
  git \
  git-lfs \
  gnupg \
  gperf \
  imagemagick \
  jq \
  lib32readline-dev \
  lib32z1-dev \
  libelf-dev \
  liblz4-tool \
  libncurses5 \
  libncurses-dev \
  libsdl1.2-dev \
  libssl-dev \
  libtinfo5 \
  libxml2 \
  libxml2-utils \
  lzop \
  openjdk-11-jdk-headless \
  p7zip-full \
  patchelf \
  pngcrush \
  python-is-python3 \
  ripgrep \
  rsync \
  schedtool \
  squashfs-tools \
  tmux \
  unzip \
  xsltproc \
  zip \
  zlib1g-dev

curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
  -o /usr/local/bin/repo
chmod 0755 /usr/local/bin/repo
git lfs install --system --skip-repo

mkdir -p \
  "$remote_root/ccache" \
  "$remote_root/local" \
  "$remote_root/logs" \
  "$remote_root/reference" \
  "$remote_root/src"

export CCACHE_DIR="$remote_root/ccache"
ccache --max-size=25G

repo version
java -version
git lfs version
ccache --version | head -n 1
df -h "$remote_root"
REMOTE
