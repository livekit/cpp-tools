#!/usr/bin/env bash
#
# Copyright 2026 LiveKit
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./cpp-tools/install.sh [OPTIONS]

Install root-level symlinks for the shared clang configuration files.

Options:
  --repo-root PATH
        Consumer repository root. Defaults to the cpp-tools superproject,
        then the Git repository containing the current working directory.
  --force
        Replace existing files or symlinks at the destination paths.
  -h, --help
        Show this help and exit.
EOF
}

tools_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root=""
force=0

while (($#)); do
  case "$1" in
    --repo-root)
      if (($# < 2)); then
        echo "ERROR: --repo-root requires a path." >&2
        exit 2
      fi
      repo_root="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${repo_root}" ]]; then
  repo_root="$(git -C "${tools_root}" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
fi
if [[ -z "${repo_root}" ]]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "${repo_root}" ]]; then
  echo "ERROR: could not determine the consumer repository root." >&2
  echo "Run this script from the consumer repository or pass --repo-root." >&2
  exit 1
fi

repo_root="$(cd "${repo_root}" && pwd -P)"
if [[ "${repo_root}" == "${tools_root}" ]]; then
  echo "ERROR: refusing to install links into the cpp-tools repository itself." >&2
  echo "Run from a consuming repository or pass --repo-root." >&2
  exit 1
fi

case "${tools_root}" in
  "${repo_root}"/*)
    tools_relative="${tools_root#"${repo_root}"/}"
    ;;
  *)
    echo "ERROR: cpp-tools must be located inside the consumer repository." >&2
    echo "cpp-tools: ${tools_root}" >&2
    echo "consumer:  ${repo_root}" >&2
    exit 1
    ;;
esac

configs=(.clang-format .clang-tidy)

# Validate every destination before changing any of them.
for config in "${configs[@]}"; do
  source_path="${tools_root}/${config}"
  destination="${repo_root}/${config}"
  link_target="${tools_relative}/${config}"

  if [[ ! -f "${source_path}" ]]; then
    echo "ERROR: shared config not found: ${source_path}" >&2
    exit 1
  fi

  if [[ -L "${destination}" ]] && [[ "$(readlink "${destination}")" == "${link_target}" ]]; then
    continue
  fi

  if [[ -e "${destination}" || -L "${destination}" ]] && ((force == 0)); then
    echo "ERROR: ${destination} already exists." >&2
    echo "Re-run with --force to replace existing config files or symlinks." >&2
    exit 1
  fi
done

for config in "${configs[@]}"; do
  destination="${repo_root}/${config}"
  link_target="${tools_relative}/${config}"

  if [[ -L "${destination}" ]] && [[ "$(readlink "${destination}")" == "${link_target}" ]]; then
    echo "Already installed: ${destination} -> ${link_target}"
    continue
  fi

  if [[ -e "${destination}" || -L "${destination}" ]]; then
    rm -f "${destination}"
  fi

  ln -s "${link_target}" "${destination}"
  echo "Installed: ${destination} -> ${link_target}"
done
