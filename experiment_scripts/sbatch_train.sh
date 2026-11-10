#!/usr/bin/env bash
# Submit one training script to Slurm.
#
# Matches the #SBATCH headers in each training script:
#   account=grp_jliang12
#   partition=htc,public
#   qos=public
#   gpus=a100:1
#   constraint=a100_80
#   cpus=16
#   mem=64G
#   time=04:00:00
#
# The job is one task. torch.distributed uses the GPU assigned to that task.
# Global batch size stays 200. Training stops after 100 cycles.
#
#   ./experiment_scripts/sbatch_train.sh <training-script> <seed>
#   sbatch experiment_scripts/mimic_only/start_mimic_only.sh 100
# Command-line sbatch flags override these arguments.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIRECTORY/.." && pwd)

usage() {
    cat <<EOF
Usage: $0 <training-script> <seed> [nvidia|gaudi]

Environment:
  ARK_SBATCH_PARTITION   default htc,public; gaudi default gaudi
  ARK_SBATCH_QOS         default public
  ARK_SBATCH_ACCOUNT     default grp_jliang12
  ARK_SBATCH_GPUS        default a100:1; gaudi default hl225:8
  ARK_SBATCH_CPUS        default 16, or 64 for gaudi
  ARK_SBATCH_MEM         default 64G, or 256G for gaudi
  ARK_SBATCH_TIME        default 04:00:00
  ARK_SBATCH_CONSTRAINT  default a100_80; unset for gaudi unless provided
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage >&2
    exit 2
fi

training_script=$1
seed=$2
container=${3:-nvidia}

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

if [[ "$training_script" != /* ]]; then
    training_script="$REPO_ROOT/$training_script"
fi
if [[ ! -f "$training_script" ]]; then
    echo "Training script not found: $training_script" >&2
    exit 2
fi
training_script=$(cd "$(dirname "$training_script")" && pwd)/$(basename "$training_script")
case "$training_script" in
    "$SCRIPT_DIRECTORY"/*) ;;
    *)
        echo "Training script must be under experiment_scripts: $training_script" >&2
        exit 2
        ;;
esac
case "$(basename "$training_script")" in
    common.sh|check_dataset_dirs.sh|sbatch_train.sh)
        echo "Refusing to submit $training_script" >&2
        exit 2
        ;;
esac

partition=htc,public
qos=public
gpus=a100:1
cpus=16
mem=64G
time_limit=04:00:00
account=grp_jliang12

if [[ "$container" == "gaudi" ]]; then
    if [[ -z "${ARK_SBATCH_PARTITION:-}" ]]; then
        partition=gaudi
    fi
    if [[ -z "${ARK_SBATCH_GPUS:-}" ]]; then
        gpus=hl225:8
    fi
    if [[ -z "${ARK_SBATCH_CPUS:-}" ]]; then
        cpus=64
    fi
    if [[ -z "${ARK_SBATCH_MEM:-}" ]]; then
        mem=256G
    fi
fi

partition=${ARK_SBATCH_PARTITION:-$partition}
qos=${ARK_SBATCH_QOS:-$qos}
gpus=${ARK_SBATCH_GPUS:-$gpus}
cpus=${ARK_SBATCH_CPUS:-$cpus}
mem=${ARK_SBATCH_MEM:-$mem}
time_limit=${ARK_SBATCH_TIME:-$time_limit}
account=${ARK_SBATCH_ACCOUNT:-$account}
if [[ "$container" == "gaudi" ]]; then
    constraint=${ARK_SBATCH_CONSTRAINT:-}
else
    constraint=${ARK_SBATCH_CONSTRAINT:-a100_80}
fi

mkdir -p "$REPO_ROOT/slurm-logs"

job_name=$(basename "$training_script" .sh)
sbatch_args=(
    --job-name "$job_name"
    --account "$account"
    --partition "$partition"
    --qos "$qos"
    --nodes 1
    --ntasks 1
    --cpus-per-task "$cpus"
    --mem "$mem"
    --time "$time_limit"
    --chdir "$REPO_ROOT"
    --output "slurm-logs/%x-%j.out"
    --error "slurm-logs/%x-%j.err"
    --export "ALL,ARK_REPO_ROOT=${REPO_ROOT},OMP_NUM_THREADS=1,PYTHONUNBUFFERED=1"
)
if [[ -n "$constraint" ]]; then
    sbatch_args+=(--constraint "$constraint")
fi
if [[ "$container" == "gaudi" ]]; then
    sbatch_args+=(--gres "gpu:${gpus}")
else
    sbatch_args+=(--gpus "$gpus")
fi

quoted_script=$(printf '%q' "$training_script")
quoted_seed=$(printf '%q' "$seed")
quoted_container=$(printf '%q' "$container")

exec sbatch "${sbatch_args[@]}" --wrap "exec ${quoted_script} ${quoted_seed} ${quoted_container}"
