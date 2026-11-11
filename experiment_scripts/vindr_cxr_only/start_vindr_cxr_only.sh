#!/usr/bin/env bash
# Sol job for grp_jliang12: public partition, one 80GB A100, 16 CPUs, 128G, 24 hours.
#SBATCH --job-name=start_vindr_cxr_only
#SBATCH --account=grp_jliang12
#SBATCH --partition=public
#SBATCH --qos=public
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gpus=a100:1
#SBATCH --constraint=a100_80
#SBATCH --mem=128G
#SBATCH --time=24:00:00
#SBATCH --mail-type=ALL
#SBATCH --mail-user=hflechsi@asu.edu
#SBATCH --output=slurm-logs/%x-%j.out
#SBATCH --error=slurm-logs/%x-%j.err
set -euo pipefail

if [[ -n "${ARK_REPO_ROOT:-}" && -f "${ARK_REPO_ROOT}/experiment_scripts/common.sh" ]]; then
    ARK_REPO_ROOT=$(cd "$ARK_REPO_ROOT" && pwd)
elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/../common.sh" ]]; then
    ARK_REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
elif [[ -n "${SLURM_SUBMIT_DIR:-}" && -f "${SLURM_SUBMIT_DIR}/experiment_scripts/common.sh" ]]; then
    ARK_REPO_ROOT=$(cd "$SLURM_SUBMIT_DIR" && pwd)
else
    echo "Cannot find experiment_scripts/common.sh. Run sbatch from the repository root, or set ARK_REPO_ROOT." >&2
    exit 2
fi
cd "$ARK_REPO_ROOT"
source "$ARK_REPO_ROOT/experiment_scripts/common.sh"

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <seed> [nvidia|gaudi]" >&2
    exit 2
fi

seed="$1"
container="${2:-nvidia}"

ark_launch_experiment \
    "$container" \
    vindr_cxr_only \
    "$seed" \
    false \
    --data_set VinDrCXR
