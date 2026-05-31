#!/bin/bash -l
#SBATCH --job-name=profid_inventory
#SBATCH --output=profid_inventory_%j.log
#SBATCH --error=profid_inventory_%j.log
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=0-12:00:00
#SBATCH --mem=64000MB
#SBATCH --mail-type=END,FAIL

set -euo pipefail

DEFAULT_REPO_ROOT="/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies"

if [ -n "${PROFID_REPO_ROOT:-}" ] && [ -f "${PROFID_REPO_ROOT}/tools/profid_data_structure_inventory.R" ]; then
  repo_root="${PROFID_REPO_ROOT}"
elif [ -n "${SLURM_SUBMIT_DIR:-}" ] && [ -f "${SLURM_SUBMIT_DIR}/tools/profid_data_structure_inventory.R" ]; then
  repo_root="${SLURM_SUBMIT_DIR}"
elif [ -f "${DEFAULT_REPO_ROOT}/tools/profid_data_structure_inventory.R" ]; then
  repo_root="${DEFAULT_REPO_ROOT}"
else
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/.." && pwd)"
fi

if [ ! -f "${repo_root}/tools/profid_data_structure_inventory.R" ]; then
  echo "ERROR: Could not find tools/profid_data_structure_inventory.R under repo root: ${repo_root}" >&2
  echo "Set PROFID_REPO_ROOT=/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies or submit from the repository root." >&2
  exit 2
fi

cd "${repo_root}"

PROFID_DATA_ROOT="${PROFID_DATA_ROOT:-/sc-projects/sc-proj-dhzc-profid/PROFID_Substudies/data}"
OUT_DIR="${PROFID_INVENTORY_OUT_DIR:-${PROFID_DATA_ROOT}/derived/data_structure}"
LOG_DIR="${PROFID_INVENTORY_LOG_DIR:-${OUT_DIR}/logs}"
MAX_FULL_READ_MB="${PROFID_INVENTORY_MAX_FULL_READ_MB:-4096}"
CHUNK_ROWS="${PROFID_INVENTORY_CHUNK_ROWS:-100000}"

if [ -z "${SLURM_JOB_ID:-}" ]; then
  mkdir -p "${LOG_DIR}"
  job_id="$(
    sbatch \
      --parsable \
      --output="${LOG_DIR}/profid_inventory_%j.log" \
      --error="${LOG_DIR}/profid_inventory_%j.log" \
      "$0" "$@"
  )"
  echo "Submitted PROFID inventory job ${job_id}"
  echo "Log file: ${LOG_DIR}/profid_inventory_${job_id}.log"
  exit 0
fi

mkdir -p "${OUT_DIR}" "${LOG_DIR}"

if [ -d "/global/work/${USER}" ]; then
  export TMPDIR="/global/work/${USER}/profid_inventory/${SLURM_JOB_ID:-manual}"
else
  export TMPDIR="${OUT_DIR}/tmp_${SLURM_JOB_ID:-manual}"
fi
mkdir -p "${TMPDIR}"

cleanup() {
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

module load R/4.5.0

echo "Started PROFID inventory at $(date)"
echo "Host: $(hostname)"
echo "Repo root: ${repo_root}"
echo "Data root: ${PROFID_DATA_ROOT}"
echo "Output directory: ${OUT_DIR}"
echo "TMPDIR: ${TMPDIR}"
echo "Max full-read MB: ${MAX_FULL_READ_MB}"
echo "Chunk rows: ${CHUNK_ROWS}"

Rscript "${repo_root}/tools/profid_data_structure_inventory.R" \
  --data-root "${PROFID_DATA_ROOT}" \
  --repo-root "${repo_root}" \
  --out-dir "${OUT_DIR}" \
  --scope source_plus_cdm \
  --include-archives yes \
  --include-availability yes \
  --max-full-read-mb "${MAX_FULL_READ_MB}" \
  --chunk-rows "${CHUNK_ROWS}" \
  --resume yes

echo "Finished PROFID inventory at $(date)"
