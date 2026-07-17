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
Usage: clang-format.sh [OPTIONS] [FILE...]

Run clang-format against a consuming repository. Defaults to check-only
(--dry-run --Werror); pass --fix to rewrite files in place.

Options:
  -h, --help, -?
        Show this help and exit.
  --repo-root PATH
        Repository root to operate on. Defaults to REPO_ROOT, then
        `git rev-parse --show-toplevel` from the current directory.
  --path PATH
        Tracked path or glob to scan when FILE... is omitted. May be repeated.
        Required unless FILE... or CLANG_FORMAT_PATHS is supplied.
  --fix, -i
        Apply formatting in place.
  --github-actions, --gh
        Force GitHub Actions annotation + step-summary mode.

Environment:
  REPO_ROOT
        Same as --repo-root.
  CLANG_FORMAT_PATHS
        Colon-separated list used when --path is not supplied.
  CLANG_FORMAT_FIX_COMMAND
        Local fix command shown in summaries. Defaults to a command matching
        the paths or files supplied to this invocation.
EOF
}

repo_root="${REPO_ROOT:-}"
paths=()
explicit_files=()
fix_mode=0
ci_mode=0
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  ci_mode=1
fi

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
    --path)
      if (($# < 2)); then
        echo "ERROR: --path requires a path." >&2
        exit 2
      fi
      paths+=("$2")
      shift 2
      ;;
    --fix|-i)
      fix_mode=1
      shift
      ;;
    --github-actions|--gh)
      ci_mode=1
      shift
      ;;
    --)
      shift
      explicit_files+=("$@")
      break
      ;;
    --*|-*)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      explicit_files+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${repo_root}" ]]; then
  repo_root="$(git rev-parse --show-toplevel)"
fi
repo_root="$(cd "${repo_root}" && pwd -P)"
cd "${repo_root}"

if ! command -v clang-format >/dev/null 2>&1; then
  echo "ERROR: clang-format not found in PATH." >&2
  echo "Install:  brew install clang-format        (macOS)" >&2
  echo "          apt install clang-format         (Linux)" >&2
  exit 1
fi

clang-format --version

if (( ${#paths[@]} == 0 )) && [[ -n "${CLANG_FORMAT_PATHS:-}" ]]; then
  IFS=':' read -r -a paths <<< "${CLANG_FORMAT_PATHS}"
fi

files=()
if (( ${#explicit_files[@]} > 0 )); then
  files=("${explicit_files[@]}")
else
  if (( ${#paths[@]} == 0 )); then
    echo "ERROR: provide at least one --path, FILE, or CLANG_FORMAT_PATHS value." >&2
    exit 2
  fi
  while IFS= read -r -d '' path; do
    files+=("${path}")
  done < <(git ls-files -z -- \
    "${paths[@]}" \
    | while IFS= read -r -d '' path; do
        case "${path}" in
          *.c|*.cc|*.cpp|*.cxx|*.h|*.hpp|*.hxx) printf '%s\0' "${path}" ;;
        esac
      done)
fi

file_count=${#files[@]}
if (( file_count == 0 )); then
  echo "clang-format: no files to process."
  exit 0
fi

fix_command="${CLANG_FORMAT_FIX_COMMAND:-}"
if [[ -z "${fix_command}" ]]; then
  fix_command="./cpp-tools/clang-format.sh --fix"
  fix_targets=()
  if (( ${#explicit_files[@]} > 0 )); then
    fix_targets=("${explicit_files[@]}")
  else
    for path in "${paths[@]}"; do
      fix_targets+=(--path "${path}")
    done
  fi
  for target in "${fix_targets[@]}"; do
    printf -v quoted_target '%q' "${target}"
    fix_command+=" ${quoted_target}"
  done
fi

log="clang-format.log"
: > "${log}"

emit_annotations() {
  local log_file="$1"
  local workspace="${GITHUB_WORKSPACE:-${PWD}}"
  local line path lineno col message rel_path

  while IFS= read -r line; do
    [[ "${line}" =~ ^(.+):([0-9]+):([0-9]+):[[:space:]]+(error|warning):[[:space:]]+(.+)[[:space:]]\[-Wclang-format-violations\][[:space:]]*$ ]] || continue
    path="${BASH_REMATCH[1]}"
    lineno="${BASH_REMATCH[2]}"
    col="${BASH_REMATCH[3]}"
    message="${BASH_REMATCH[5]}"
    rel_path="${path#${workspace}/}"
    message="${message//$'%'/%25}"
    message="${message//$'\r'/%0D}"
    message="${message//$'\n'/%0A}"
    printf '::error file=%s,line=%s,col=%s,title=clang-format::%s\n' \
      "${rel_path}" "${lineno}" "${col}" "${message}"
  done < "${log_file}"
}

write_step_summary() {
  local log_file="$1"
  local summary_file="${GITHUB_STEP_SUMMARY:-}"
  [[ -n "${summary_file}" ]] || return 0

  local workspace="${GITHUB_WORKSPACE:-${PWD}}"
  local files_tsv
  files_tsv="$(mktemp -t fmt-files.XXXXXX)"

  local sline spath slineno
  declare -A seen=()
  while IFS= read -r sline; do
    [[ "${sline}" =~ ^(.+):([0-9]+):([0-9]+):[[:space:]]+(error|warning):[[:space:]]+(.+)[[:space:]]\[-Wclang-format-violations\][[:space:]]*$ ]] || continue
    spath="${BASH_REMATCH[1]#${workspace}/}"
    slineno="${BASH_REMATCH[2]}"
    if [[ -z "${seen[${spath}]:-}" ]]; then
      seen[${spath}]=1
      printf '%s\t%s\n' "${spath}" "${slineno}" >> "${files_tsv}"
    fi
  done < "${log_file}"

  local violation_files
  violation_files=$(wc -l < "${files_tsv}" | tr -d ' ')
  local repo_url=""
  if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
    local blob_sha="${FORMAT_BLOB_SHA:-${GITHUB_SHA:-}}"
    if [[ -n "${blob_sha}" ]]; then
      repo_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/blob/${blob_sha}"
    fi
  fi

  {
    echo "## clang-format results"
    echo
    if (( violation_files == 0 )); then
      echo ":white_check_mark: All files are properly formatted."
    else
      echo ":x: ${violation_files} file(s) need formatting."
      echo
      echo "<details><summary>Files needing formatting</summary>"
      echo
      echo '| File |'
      echo '|------|'
      while IFS=$'\t' read -r path lineno; do
        local file_cell
        if [[ -n "${repo_url}" && "${path}" != /* ]]; then
          file_cell="[\`${path}\`](${repo_url}/${path}#L${lineno})"
        else
          file_cell="\`${path}\`"
        fi
        printf '| %s |\n' "${file_cell}"
      done < "${files_tsv}"
      echo
      echo "</details>"
      echo
      echo "Run \`${fix_command}\` locally to apply formatting."
    fi
  } >> "${summary_file}"

  rm -f "${files_tsv}"
}

print_stdout_summary() {
  local log_file="$1"
  local total="$2"
  local files_tsv
  files_tsv="$(mktemp -t fmt-stdout.XXXXXX)"

  local line spath
  declare -A seen=()
  while IFS= read -r line; do
    [[ "${line}" =~ ^(.+):([0-9]+):([0-9]+):[[:space:]]+(error|warning):[[:space:]]+(.+)[[:space:]]\[-Wclang-format-violations\][[:space:]]*$ ]] || continue
    spath="${BASH_REMATCH[1]}"
    if [[ -z "${seen[${spath}]:-}" ]]; then
      seen[${spath}]=1
      echo "${spath}" >> "${files_tsv}"
    fi
  done < "${log_file}"

  local violation_files
  violation_files=$(wc -l < "${files_tsv}" | tr -d ' ')

  echo "------------------------------------------------------------"
  if (( violation_files == 0 )); then
    printf 'clang-format summary: clean (%d file(s) checked)\n' "${total}"
  else
    printf 'clang-format summary: %d of %d file(s) need formatting\n' \
      "${violation_files}" "${total}"
    echo "  files:"
    while IFS= read -r f; do
      printf '    %s\n' "${f}"
    done < "${files_tsv}"
    echo
    echo "  Run '${fix_command}' to apply formatting."
  fi
  echo "------------------------------------------------------------"

  rm -f "${files_tsv}"
  __FMT_VIOLATION_FILES="${violation_files}"
}

__hash_files() {
  if (( ${#files[@]} == 0 )); then
    return
  fi
  printf '%s\n' "${files[@]}" | git hash-object --stdin-paths
}

pre_hashes=()
if (( fix_mode == 1 )); then
  while IFS= read -r __h; do
    pre_hashes+=("${__h}")
  done < <(__hash_files)
fi

set +e
if (( fix_mode == 1 )); then
  printf '%s\0' "${files[@]}" | xargs -0 clang-format -i >"${log}" 2>&1
  rc=$?
else
  printf '%s\0' "${files[@]}" | xargs -0 clang-format --dry-run --Werror >"${log}" 2>&1
  rc=$?
fi
set -e

changed_files=()
if (( fix_mode == 1 )); then
  post_hashes=()
  while IFS= read -r __h; do
    post_hashes+=("${__h}")
  done < <(__hash_files)
  for i in "${!files[@]}"; do
    if [[ "${pre_hashes[$i]:-}" != "${post_hashes[$i]:-}" ]]; then
      changed_files+=("${files[$i]}")
    fi
  done
fi

if (( fix_mode == 0 )); then
  cat "${log}"
fi

if [[ "${ci_mode}" == "1" ]] && (( fix_mode == 0 )); then
  emit_annotations "${log}"
  write_step_summary "${log}"
fi

__FMT_VIOLATION_FILES=0
if (( fix_mode == 1 )); then
  echo "------------------------------------------------------------"
  if (( ${#changed_files[@]} == 0 )); then
    printf 'clang-format summary: clean (0 of %d file(s) needed formatting)\n' "${file_count}"
  else
    printf 'clang-format summary: formatted %d of %d file(s)\n' "${#changed_files[@]}" "${file_count}"
    echo "  files:"
    for __cf in "${changed_files[@]}"; do
      printf '    %s\n' "${__cf}"
    done
  fi
  echo "------------------------------------------------------------"
else
  print_stdout_summary "${log}" "${file_count}"
fi

if [[ -s "${log}" ]]; then
  echo "Results written to: $(pwd)/${log}"
else
  rm -f "${log}"
fi

if (( fix_mode == 1 )); then
  exit "${rc}"
fi

if (( rc == 0 )); then
  exit 0
elif (( rc == 123 )) || (( __FMT_VIOLATION_FILES > 0 )); then
  exit 1
else
  exit "${rc}"
fi
