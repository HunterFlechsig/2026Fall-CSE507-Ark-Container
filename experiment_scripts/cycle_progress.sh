#!/usr/bin/env bash
# Report completed training cycles for every experiment.
#
# A cycle counts as completed when its saved weights or checkpoint exists.
# Run directories are <experiment>_seed_<seed> in the repository root.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIRECTORY/.." && pwd)

planned_cycles() {
    awk '/^[[:space:]]*--pretrain_epochs[[:space:]]+/ { print $2; exit }' \
        "$SCRIPT_DIRECTORY/common.sh"
}

run_completed_cycles() {
    local run_directory="$1"
    local highest=-1
    local entry
    local cycle
    local checkpoint_name

    shopt -s nullglob
    for entry in "$run_directory"/models/weights/epoch_*; do
        [[ -d "$entry" ]] || continue
        cycle=${entry##*/epoch_}
        cycle=$((10#$cycle))
        if (( cycle > highest )); then
            highest=$cycle
        fi
    done
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

    if (( highest < 0 )); then
        printf '0\n'
    else
        printf '%s\n' "$highest"
    fi
}

run_logged_cycle() {
    local train_log="$1"
    local highest=0
    local cycle

    [[ -f "$train_log" ]] || return 0
    while IFS= read -r cycle; do
        [[ -n "$cycle" ]] || continue
        if (( 10#$cycle > highest )); then
            highest=$((10#$cycle))
        fi
    done < <(sed -n 's/.*Cycle=\([0-9][0-9]*\).*/\1/p' "$train_log")
    if (( highest > 0 )); then
        printf '%s\n' "$highest"
    fi
}

run_planned_cycles() {
    local train_log="$1"
    local planned
    local default_planned="$2"

    if [[ -f "$train_log" ]]; then
        planned=$(sed -n '/Warmup Cycles:/d; s/.*Cycles:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$train_log" | tail -n 1)
        if [[ -n "$planned" ]]; then
            printf '%s\n' "$planned"
            return 0
        fi
    fi
    printf '%s\n' "$default_planned"
}

default_planned=$(planned_cycles)
if [[ ! "$default_planned" =~ ^[0-9]+$ ]]; then
    echo "Could not read --pretrain_epochs from experiment_scripts/common.sh" >&2
    exit 1
fi

declare -A seen_runs=()
declare -a rows=()

shopt -s nullglob
for run_directory in "$REPO_ROOT"/*_seed_*; do
    [[ -d "$run_directory" ]] || continue
    run_name=$(basename "$run_directory")
    if [[ ! "$run_name" =~ ^(.+)_seed_([0-9]+)$ ]]; then
        continue
    fi
    experiment=${BASH_REMATCH[1]}
    seed=${BASH_REMATCH[2]}
    seen_runs["$experiment"]=1
    completed=$(run_completed_cycles "$run_directory")
    planned=$(run_planned_cycles "$run_directory/train.log" "$default_planned")
    logged=$(run_logged_cycle "$run_directory/train.log" || true)
    if (( completed >= planned )); then
        status="complete"
    elif [[ -n "$logged" && "$logged" =~ ^[0-9]+$ ]] && (( logged > completed )); then
        status="cycle ${logged} in progress"
    elif (( completed == 0 )); then
        status="no completed cycle"
    else
        status="resume from cycle ${completed}"
    fi
    rows+=("$(printf '%s\t%s\t%s\t%s' "$experiment" "$seed" "${completed}/${planned}" "$status")")
done

for start_script in "$SCRIPT_DIRECTORY"/*/start_*.sh; do
    [[ -f "$start_script" ]] || continue
    experiment=$(basename "$(dirname "$start_script")")
    if [[ -z "${seen_runs[$experiment]:-}" ]]; then
        rows+=("$(printf '%s\t%s\t%s\t%s' "$experiment" "-" "0/${default_planned}" "not started")")
    fi
done
shopt -u nullglob

printf '%-64s %8s %12s %s\n' "EXPERIMENT" "SEED" "COMPLETED" "STATUS"
if (( ${#rows[@]} == 0 )); then
    exit 0
fi
printf '%s\n' "${rows[@]}" | sort -t $'\t' -k1,1 -k2,2n | while IFS=$'\t' read -r experiment seed completed status; do
    printf '%-64s %8s %12s %s\n' "$experiment" "$seed" "$completed" "$status"
done
