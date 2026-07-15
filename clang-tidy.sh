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
Usage: clang-tidy.sh [OPTIONS] [FILE...] [run-clang-tidy args...]

Run clang-tidy against a consuming repository. The repository must have a
compile_commands.json under the configured build directory.

Options:
  -h, --help, -?
        Show this help and exit.
  --repo-root PATH
        Repository root to operate on. Defaults to REPO_ROOT, then
        `git rev-parse --show-toplevel` from the current directory.
  --build-dir PATH
        Build directory containing compile_commands.json. Default:
        CLANG_TIDY_BUILD_DIR or build-release.
  --file-regex REGEX
        run-clang-tidy target regex used when FILE... is omitted. Default:
        CLANG_TIDY_FILE_REGEX or all non-test src/*.c/cpp/cc/cxx files.
  --header-filter REGEX
        Forwarded to run-clang-tidy as -header-filter.
  --exclude-header-filter REGEX
        Forwarded to run-clang-tidy as -exclude-header-filter.
  --require-generated-protobuf PATH
        Require PATH to contain *.pb.h before running. May be relative to
        the repo root. Useful for protobuf-backed SDKs.
  --fix
        Apply fixes in place (forwarded to run-clang-tidy as -fix).
  --github-actions, --gh
        Force GitHub Actions annotation + step-summary mode.
  --fail-on-warning, --strict
        Exit non-zero when any warning is emitted.

Environment:
  REPO_ROOT, CLANG_TIDY_BUILD_DIR, CLANG_TIDY_FILE_REGEX,
  CLANG_TIDY_HEADER_FILTER, CLANG_TIDY_EXCLUDE_HEADER_FILTER,
  CLANG_TIDY_REQUIRE_GENERATED_PROTOBUF
        Environment equivalents for the matching options above.
EOF
}

repo_root="${REPO_ROOT:-}"
build_dir="${CLANG_TIDY_BUILD_DIR:-build-release}"
default_file_regex='^(?!.*/(_deps|build-[^/]*|vcpkg_installed|docker|docs|data)/).*/src/(?!tests/).*\.(c|cpp|cc|cxx)$'
file_regex="${CLANG_TIDY_FILE_REGEX:-${default_file_regex}}"
header_filter="${CLANG_TIDY_HEADER_FILTER:-}"
exclude_header_filter="${CLANG_TIDY_EXCLUDE_HEADER_FILTER:-}"
required_proto_dir="${CLANG_TIDY_REQUIRE_GENERATED_PROTOBUF:-}"
ci_mode=0
fail_on_warning=0
forward_args=()
explicit_files=()

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
    --build-dir)
      if (($# < 2)); then
        echo "ERROR: --build-dir requires a path." >&2
        exit 2
      fi
      build_dir="$2"
      shift 2
      ;;
    --file-regex)
      if (($# < 2)); then
        echo "ERROR: --file-regex requires a regex." >&2
        exit 2
      fi
      file_regex="$2"
      shift 2
      ;;
    --header-filter)
      if (($# < 2)); then
        echo "ERROR: --header-filter requires a regex." >&2
        exit 2
      fi
      header_filter="$2"
      shift 2
      ;;
    --exclude-header-filter)
      if (($# < 2)); then
        echo "ERROR: --exclude-header-filter requires a regex." >&2
        exit 2
      fi
      exclude_header_filter="$2"
      shift 2
      ;;
    --require-generated-protobuf)
      if (($# < 2)); then
        echo "ERROR: --require-generated-protobuf requires a path." >&2
        exit 2
      fi
      required_proto_dir="$2"
      shift 2
      ;;
    --fix)
      forward_args+=("-fix")
      shift
      ;;
    --github-actions|--gh)
      ci_mode=1
      shift
      ;;
    --fail-on-warning|--strict)
      fail_on_warning=1
      shift
      ;;
    --)
      shift
      forward_args+=("$@")
      break
      ;;
    --*)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    -*)
      forward_args+=("$1")
      shift
      ;;
    *)
      if [[ -f "$1" ]]; then
        explicit_files+=("$1")
      else
        forward_args+=("$1")
      fi
      shift
      ;;
  esac
done

if [[ -z "${repo_root}" ]]; then
  repo_root="$(git rev-parse --show-toplevel)"
fi
repo_root="$(cd "${repo_root}" && pwd -P)"
cd "${repo_root}"

if [[ ! -f "${build_dir}/compile_commands.json" ]]; then
  echo "ERROR: ${build_dir}/compile_commands.json not found." >&2
  echo "Run the consuming repository's release/configure build first." >&2
  exit 1
fi

if [[ -n "${required_proto_dir}" ]]; then
  if [[ ! -d "${required_proto_dir}" ]] || ! compgen -G "${required_proto_dir}/*.pb.h" >/dev/null; then
    echo "ERROR: no generated protobuf headers found in ${required_proto_dir}/." >&2
    echo "Run the consuming repository's protobuf/header generation step first." >&2
    exit 1
  fi
fi

if ! command -v run-clang-tidy >/dev/null 2>&1; then
  echo "ERROR: run-clang-tidy not found in PATH." >&2
  echo "Install LLVM:  brew install llvm   (macOS)" >&2
  echo "               apt install clang-tools-NN   (Linux)" >&2
  exit 1
fi

extra_args=(-extra-arg=-Wno-gnu-zero-variadic-macro-arguments)
if [[ "$(uname)" == "Darwin" ]]; then
  sdk_path="$(xcrun --show-sdk-path 2>/dev/null || true)"
  if [[ -n "${sdk_path}" ]]; then
    extra_args+=(-extra-arg="-isysroot${sdk_path}")
  fi
fi

filter_args=()
if [[ -n "${header_filter}" ]]; then
  filter_args+=("-header-filter=${header_filter}")
fi
if [[ -n "${exclude_header_filter}" ]]; then
  filter_args+=("-exclude-header-filter=${exclude_header_filter}")
fi

if command -v nproc >/dev/null 2>&1; then
  jobs=$(nproc)
else
  jobs=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
fi

emit_annotations() {
  local log="$1"
  local workspace="${GITHUB_WORKSPACE:-${PWD}}"
  local line path lineno col severity message check rel_path

  while IFS= read -r line; do
    [[ "${line}" =~ ^(.+):([0-9]+):([0-9]+):[[:space:]]+(warning|error):[[:space:]]+(.+)[[:space:]]\[([^]]+)\][[:space:]]*$ ]] || continue
    path="${BASH_REMATCH[1]}"
    lineno="${BASH_REMATCH[2]}"
    col="${BASH_REMATCH[3]}"
    severity="${BASH_REMATCH[4]}"
    message="${BASH_REMATCH[5]}"
    check="${BASH_REMATCH[6]}"
    check="${check%,-warnings-as-errors}"
    rel_path="${path#${workspace}/}"
    message="${message//$'%'/%25}"
    message="${message//$'\r'/%0D}"
    message="${message//$'\n'/%0A}"
    printf '::%s file=%s,line=%s,col=%s,title=clang-tidy (%s)::%s\n' \
      "${severity}" "${rel_path}" "${lineno}" "${col}" "${check}" "${message}"
  done < "${log}"
}

check_link() {
  local name="$1"
  local module="${name%%-*}"
  local rest="${name#*-}"
  case "${name}" in
    clang-diagnostic-*)
      printf '`%s`' "${name}"
      ;;
    clang-analyzer-*)
      printf '[`%s`](https://clang.llvm.org/docs/analyzer/checkers.html)' "${name}"
      ;;
    *)
      printf '[`%s`](https://clang.llvm.org/extra/clang-tidy/checks/%s/%s.html)' \
        "${name}" "${module}" "${rest}"
      ;;
  esac
}

write_step_summary() {
  local log="$1"
  local summary_file="${GITHUB_STEP_SUMMARY:-}"
  [[ -n "${summary_file}" ]] || return 0

  local workspace="${GITHUB_WORKSPACE:-${PWD}}"
  local findings_tsv
  findings_tsv="$(mktemp -t tidy-findings.XXXXXX)"

  local sline spath slineno scol sseverity smessage scheck
  while IFS= read -r sline; do
    [[ "${sline}" =~ ^(.+):([0-9]+):([0-9]+):[[:space:]]+(warning|error):[[:space:]]+(.+)[[:space:]]\[([^]]+)\][[:space:]]*$ ]] || continue
    spath="${BASH_REMATCH[1]#${workspace}/}"
    slineno="${BASH_REMATCH[2]}"
    scol="${BASH_REMATCH[3]}"
    sseverity="${BASH_REMATCH[4]}"
    smessage="${BASH_REMATCH[5]}"
    scheck="${BASH_REMATCH[6]}"
    scheck="${scheck%,-warnings-as-errors}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${sseverity}" "${spath}" "${slineno}" "${scol}" "${scheck}" "${smessage}" >> "${findings_tsv}"
  done < "${log}"

  local warnings errors total
  warnings=$(awk -F'\t' '$1=="warning"{c++} END{print c+0}' "${findings_tsv}")
  errors=$(awk -F'\t' '$1=="error"{c++} END{print c+0}' "${findings_tsv}")
  total=$((warnings + errors))

  local repo_url=""
  if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
    local blob_sha="${TIDY_BLOB_SHA:-${GITHUB_SHA:-}}"
    if [[ -n "${blob_sha}" ]]; then
      repo_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/blob/${blob_sha}"
    fi
  fi

  {
    echo "## clang-tidy results"
    echo
    if (( total == 0 )); then
      echo ":white_check_mark: All files passed the configured checks."
    else
      echo "| Severity | Count |"
      echo "|----------|-------|"
      echo "| :x: Error | ${errors} |"
      echo "| :warning: Warning | ${warnings} |"
      echo
      echo "### Top checks"
      echo
      echo '| Check | Count |'
      echo '|-------|-------|'
      awk -F'\t' '{print $5}' "${findings_tsv}" \
        | sort | uniq -c | sort -rn | head -5 \
        | while read -r count name; do
            printf '| %s | %d |\n' "$(check_link "${name}")" "${count}"
          done
      echo
      echo "<details><summary>All ${total} findings</summary>"
      echo
      echo '| Severity | File | Check | Message |'
      echo '|----------|------|-------|---------|'
      {
        awk -F'\t' '$1=="error"' "${findings_tsv}"
        awk -F'\t' '$1=="warning"' "${findings_tsv}"
      } | while IFS=$'\t' read -r sev path lineno col check msg; do
        msg="${msg//|/\\|}"
        local icon label file_cell
        if [[ "${sev}" == "error" ]]; then
          icon=':x:'
          label='Error'
        else
          icon=':warning:'
          label='Warning'
        fi
        if [[ -n "${repo_url}" && "${path}" != /* ]]; then
          file_cell="[\`${path}:${lineno}\`](${repo_url}/${path}#L${lineno})"
        else
          file_cell="\`${path}:${lineno}\`"
        fi
        printf '| %s %s | %s | %s | %s |\n' \
          "${icon}" "${label}" "${file_cell}" "$(check_link "${check}")" "${msg}"
      done
      echo
      echo "</details>"
      echo
    fi
  } >> "${summary_file}"

  rm -f "${findings_tsv}"
}

print_stdout_summary() {
  local log="$1"
  local checks_tsv
  checks_tsv="$(mktemp -t tidy-stdout.XXXXXX)"

  local line severity check
  while IFS= read -r line; do
    [[ "${line}" =~ ^(.+):([0-9]+):([0-9]+):[[:space:]]+(warning|error):[[:space:]]+(.+)[[:space:]]\[([^]]+)\][[:space:]]*$ ]] || continue
    severity="${BASH_REMATCH[4]}"
    check="${BASH_REMATCH[6]}"
    check="${check%,-warnings-as-errors}"
    printf '%s\t%s\n' "${severity}" "${check}" >> "${checks_tsv}"
  done < "${log}"

  local warnings errors
  warnings=$(awk -F'\t' '$1=="warning"{c++} END{print c+0}' "${checks_tsv}")
  errors=$(awk -F'\t' '$1=="error"{c++} END{print c+0}' "${checks_tsv}")

  echo "------------------------------------------------------------"
  if (( warnings == 0 && errors == 0 )); then
    echo "clang-tidy summary: clean (0 warnings, 0 errors)"
  else
    printf 'clang-tidy summary: %d warning(s), %d error(s)\n' "${warnings}" "${errors}"
    echo "  by check:"
    awk -F'\t' '{print $2}' "${checks_tsv}" \
      | sort | uniq -c | sort -rn \
      | while read -r count name; do
          printf '    %-50s %d\n' "${name}" "${count}"
        done
  fi
  echo "------------------------------------------------------------"

  rm -f "${checks_tsv}"
  __TIDY_WARNINGS="${warnings}"
  __TIDY_ERRORS="${errors}"
}

log="clang-tidy.log"
if (( ${#explicit_files[@]} > 0 )); then
  tidy_targets=("${explicit_files[@]}")
else
  tidy_targets=("${file_regex}")
fi

set +e
PYTHONUNBUFFERED=1 run-clang-tidy \
  -p "${build_dir}" \
  -quiet \
  -j "${jobs}" \
  ${filter_args[@]+"${filter_args[@]}"} \
  ${extra_args[@]+"${extra_args[@]}"} \
  ${forward_args[@]+"${forward_args[@]}"} \
  "${tidy_targets[@]}" \
  2>&1 | tee "${log}"
rc="${PIPESTATUS[0]}"
set -e

if [[ "${ci_mode}" == "1" ]]; then
  emit_annotations "${log}"
  write_step_summary "${log}"
fi

__TIDY_WARNINGS=0
__TIDY_ERRORS=0
print_stdout_summary "${log}"

if (( __TIDY_WARNINGS > 0 || __TIDY_ERRORS > 0 )); then
  echo "Results written to: $(cd "$(dirname "${log}")" && pwd)/$(basename "${log}")"
else
  rm -f "${log}"
fi

if [[ "${fail_on_warning}" == "1" && "${rc}" == "0" && "${__TIDY_WARNINGS}" -gt 0 ]]; then
  echo "clang-tidy: --fail-on-warning is set and ${__TIDY_WARNINGS} warning(s) were emitted; exiting non-zero." >&2
  rc=1
fi

exit "${rc}"
