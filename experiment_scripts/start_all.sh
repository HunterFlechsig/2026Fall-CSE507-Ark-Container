#!/usr/bin/env bash
# Submit one Slurm job for each selected experiment. Every job uses the same seed.
# Concurrent jobs use random sampling.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIRECTORY/.." && pwd)

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <seed> [nvidia|gaudi]" >&2
    exit 2
fi

seed="$1"
container="${2:-nvidia}"

if [[ ! "$seed" =~ ^-?[0-9]+$ ]]; then
    echo "Seed must be an integer: $seed" >&2
    exit 2
fi
case "$container" in
    nvidia|gaudi) ;;
    *)
        echo "Container must be nvidia or gaudi: $container" >&2
        exit 2
        ;;
esac

scripts=(
    experiment_scripts/vindr_cxr_only/start_vindr_cxr_only.sh
    experiment_scripts/chestxray14_only/start_chestxray14_only.sh
    experiment_scripts/mimic_only/start_mimic_only.sh
    experiment_scripts/chexpert_only/start_chexpert_only.sh
    experiment_scripts/vindr_cxr_chestxray14_cyclic/start_vindr_cxr_chestxray14_cyclic.sh
    experiment_scripts/vindr_cxr_chestxray14_concurrent_random_sampling/start_vindr_cxr_chestxray14_concurrent_random_sampling.sh
    experiment_scripts/vindr_cxr_chestxray14_mimic_chexpert_cyclic/start_vindr_cxr_chestxray14_mimic_chexpert_cyclic.sh
    experiment_scripts/vindr_cxr_chestxray14_mimic_chexpert_concurrent_random_sampling/start_vindr_cxr_chestxray14_mimic_chexpert_concurrent_random_sampling.sh
)

for script in "${scripts[@]}"; do
    if [[ ! -f "$REPO_ROOT/$script" ]]; then
        echo "Missing training script: $REPO_ROOT/$script" >&2
        exit 1
    fi
done

cd "$REPO_ROOT"
mkdir -p "$REPO_ROOT/slurm-logs"
"$SCRIPT_DIRECTORY/check_dataset_dirs.sh" VinDrCXR ChestXray14 MIMIC CheXpert

for script in "${scripts[@]}"; do
    echo "Submitting $script"
    sbatch "$REPO_ROOT/$script" "$seed" "$container"
done
