#!/usr/bin/env bash
# Sol job for grp_jliang12: htc or public, 1 GPU, 16 CPUs, 64G, 4 hours.
#SBATCH --job-name=resume_vindr_cxr_chestxray14_concurrent_random_sampling
#SBATCH --account=grp_jliang12
#SBATCH --partition=htc,public
#SBATCH --qos=public
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gpus=1
#SBATCH --mem=64G
#SBATCH --time=04:00:00
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
    vindr_cxr_chestxray14_concurrent_random_sampling \
    "$seed" \
    true \
    --data_set VinDrCXR \
    --data_set ChestXray14 \
    --training_strategy joint \
    --joint_sampling proportional
