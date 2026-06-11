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
Usage: install-pre-commit.sh [--repo-root PATH]

Install a git pre-commit hook that runs clang-format on staged C/C++ files.
The generated hook prefers a consuming repo compatibility wrapper at
./scripts/clang-format.sh and falls back to ./cpp-tools/scripts/clang-format.sh.
EOF
}

repo_root="${REPO_ROOT:-}"
while (($#)); do
  case "$1" in
    -h|--help|-\?)
      usage
      exit 0
      ;;
    --repo-root)
      if (($# < 2)); then
        echo "ERROR: --repo-root requires a path." >&2
        exit 2
      fi
      repo_root="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${repo_root}" ]]; then
  repo_root="$(git rev-parse --show-toplevel)"
fi
repo_root="$(cd "${repo_root}" && pwd -P)"
hook_path="${repo_root}/.git/hooks/pre-commit"

cat >"${hook_path}" <<'HOOK'
#!/bin/sh
# Auto-format staged C/C++ files using LiveKit C++ tooling.
files=$(git diff --cached --name-only --diff-filter=ACMR \
  -- "*.c" "*.cc" "*.cpp" "*.cxx" "*.h" "*.hpp" "*.hxx")
[ -z "${files}" ] && exit 0

if [ -x "./scripts/clang-format.sh" ]; then
  echo "${files}" | xargs ./scripts/clang-format.sh --fix
elif [ -x "./cpp-tools/scripts/clang-format.sh" ]; then
  repo_root=$(git rev-parse --show-toplevel)
  echo "${files}" | xargs ./cpp-tools/scripts/clang-format.sh --repo-root "${repo_root}" --fix
else
  echo "ERROR: no LiveKit clang-format wrapper found." >&2
  exit 1
fi

echo "${files}" | xargs git add
HOOK

chmod +x "${hook_path}"
echo "Installed pre-commit hook at ${hook_path}"
