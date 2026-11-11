#!/usr/bin/env bash
# Resume one Slurm job for each selected experiment that has an unfinished run.
# Every job uses the same seed. Concurrent jobs use random sampling.
# Runs with no directory, no checkpoint, or a finished cycle count are skipped.
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
    experiment_scripts/vindr_cxr_only/resume_vindr_cxr_only.sh
    experiment_scripts/chestxray14_only/resume_chestxray14_only.sh
    experiment_scripts/mimic_only/resume_mimic_only.sh
    experiment_scripts/chexpert_only/resume_chexpert_only.sh
    experiment_scripts/vindr_cxr_chestxray14_cyclic/resume_vindr_cxr_chestxray14_cyclic.sh
    experiment_scripts/vindr_cxr_chestxray14_concurrent_random_sampling/resume_vindr_cxr_chestxray14_concurrent_random_sampling.sh
    experiment_scripts/vindr_cxr_chestxray14_mimic_chexpert_cyclic/resume_vindr_cxr_chestxray14_mimic_chexpert_cyclic.sh
    experiment_scripts/vindr_cxr_chestxray14_mimic_chexpert_concurrent_random_sampling/resume_vindr_cxr_chestxray14_mimic_chexpert_concurrent_random_sampling.sh
)

for script in "${scripts[@]}"; do
    if [[ ! -f "$REPO_ROOT/$script" ]]; then
        echo "Missing training script: $REPO_ROOT/$script" >&2
        exit 1
    fi
done

highest_checkpoint_cycle() {
    local run_directory="$1"
    local highest=-1
    local entry
    local cycle
    local checkpoint_name

    shopt -s nullglob
    for entry in "$run_directory"/models/checkpoints/cycle_*.pth.tar; do
        [[ -f "$entry" ]] || continue
        checkpoint_name=$(basename "$entry")
        cycle=${checkpoint_name#cycle_}
        cycle=${cycle%%_*}
        cycle=$((10#$cycle))
        if (( cycle > highest )); then
            highest=$cycle
        fi
    done
    shopt -u nullglob
    printf '%s\n' "$highest"
}

planned_cycles() {
    local train_log="$1"
    local planned

    if [[ -f "$train_log" ]]; then
        planned=$(sed -n '/Warmup Cycles:/d; s/.*Cycles:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$train_log" | tail -n 1)
        if [[ -n "$planned" ]]; then
            printf '%s\n' "$planned"
            return 0
        fi
    fi
    awk '/^[[:space:]]*--pretrain_epochs[[:space:]]+/ { print $2; exit }' \
        "$SCRIPT_DIRECTORY/common.sh"
}

cd "$REPO_ROOT"
mkdir -p "$REPO_ROOT/slurm-logs"
"$SCRIPT_DIRECTORY/check_dataset_dirs.sh" VinDrCXR ChestXray14 MIMIC CheXpert

submitted=0
for script in "${scripts[@]}"; do
    experiment=$(basename "$(dirname "$script")")
    run_directory="$REPO_ROOT/${experiment}_seed_${seed}"
    if [[ ! -d "$run_directory" ]]; then
        echo "Skipping $experiment: no run for seed $seed"
        continue
    fi
    completed=$(highest_checkpoint_cycle "$run_directory")
    if (( completed < 0 )); then
        echo "Skipping $experiment: no checkpoint for seed $seed"
        continue
    fi
    planned=$(planned_cycles "$run_directory/train.log")
    if (( completed >= planned )); then
        echo "Skipping $experiment: cycle $completed of $planned is already complete"
        continue
    fi
    echo "Submitting $script from cycle $completed"
    sbatch "$REPO_ROOT/$script" "$seed" "$container"
    submitted=$((submitted + 1))
done

echo "Submitted $submitted resume job(s)"
