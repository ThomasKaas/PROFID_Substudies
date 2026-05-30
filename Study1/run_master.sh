#!/usr/bin/env bash

# Shell entry point for the Study1 R master runner.
#
# The HPC does not expose Rscript until an R module is loaded. This wrapper
# tries to load R through the module system before delegating to master_run.R.
#
# Examples:
#   ./Study1/run_master.sh
#   ./Study1/run_master.sh --dry-run
#   STUDY1_R_MODULE='R/3.5.0-iomkl-2018a-X11-20180131' ./Study1/run_master.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

init_modules() {
  if command -v module >/dev/null 2>&1 || command -v ml >/dev/null 2>&1; then
    return 0
  fi

  local init_file
  for init_file in \
    /etc/profile.d/modules.sh \
    /usr/share/lmod/lmod/init/bash \
    /usr/share/Modules/init/bash
  do
    if [ -r "${init_file}" ]; then
      # shellcheck disable=SC1090
      source "${init_file}"
      return 0
    fi
  done
}

load_r_module_if_needed() {
  if command -v Rscript >/dev/null 2>&1; then
    return 0
  fi

  init_modules || true

  if [ -n "${STUDY1_R_MODULE:-}" ]; then
    if command -v ml >/dev/null 2>&1; then
      ml "${STUDY1_R_MODULE}"
    elif command -v module >/dev/null 2>&1; then
      module load "${STUDY1_R_MODULE}"
    fi
  elif command -v ml >/dev/null 2>&1; then
    ml R || true
  elif command -v module >/dev/null 2>&1; then
    module load R || true
  fi
}

load_r_module_if_needed

if ! command -v Rscript >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ERROR: Rscript is still not available.

On this HPC, R is loaded through environment modules. Try:

  ml avail -r '^R/'
  ml R/<version-shown-by-ml-avail>
  Rscript Study1/master_run.R --dry-run

Or run this wrapper with an explicit module name, for example:

  STUDY1_R_MODULE='R/3.5.0-iomkl-2018a-X11-20180131' ./Study1/run_master.sh --dry-run

EOF
  exit 127
fi

cd "${repo_root}"
exec Rscript "${script_dir}/master_run.R" "$@"
