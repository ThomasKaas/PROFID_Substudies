#!/bin/bash -l
#SBATCH --job-name=study3
#SBATCH --mail-user=thomas.kaas@charite.de
#SBATCH --mail-type=BEGIN,END,FAIL,REQUEUE

set -euo pipefail

email="thomas.kaas@charite.de"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
timestamp="${STUDY3_RUN_TIMESTAMP:-$(date '+%d-%m-%Y-%H-%M-%S')}"
log_dir="${repo_root}/Study3/Outputs"
log_file="${log_dir}/log_run_${timestamp}.log"

send_mail() {
  printf '%s\n' "$2" | ssh stallo-1.local "mail -s '$1' '${email}'" || true
}

mkdir -p "${log_dir}"

if [ -z "${SLURM_JOB_ID:-}" ]; then
  export STUDY3_RUN_TIMESTAMP="${timestamp}"
  job_id="$(
    sbatch \
      --parsable \
      --output="${log_file}" \
      --error="${log_file}" \
      "${script_dir}/run_study3.sh" "$@"
  )"

  send_mail \
    "Study3 job submitted" \
    "Study3 job ${job_id} was submitted at $(date). Log file: ${log_file}"

  echo "Submitted Study3 job ${job_id}"
  echo "Log file: ${log_file}"
  exit 0
fi

on_cancel() {
  send_mail \
    "Study3 job canceled" \
    "Study3 job ${SLURM_JOB_ID} was canceled at $(date). Log file: ${log_file}"
  exit 130
}

trap on_cancel INT TERM

cd "${repo_root}"

module load R/4.5.0
Rscript Study3/master_run.R "$@"
