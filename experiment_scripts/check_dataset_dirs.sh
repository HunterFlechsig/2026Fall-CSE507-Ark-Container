#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIRECTORY/.." && pwd)
DATASETS_CONFIG="$REPO_ROOT/base/datasets_config.yaml"

usage() {
    echo "Usage: $0 [Dataset ...]" >&2
    echo "Checks data_dir from base/datasets_config.yaml." >&2
    echo "With no arguments, every dataset in that file is checked." >&2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! -f "$DATASETS_CONFIG" ]]; then
    echo "Dataset config not found: $DATASETS_CONFIG" >&2
    exit 2
fi

dataset_data_dir() {
    local dataset="$1"
    awk -v dataset="$dataset" '
        $0 ~ "^" dataset ":[[:space:]]*$" { in_dataset = 1; next }
        in_dataset && /^[^[:space:]]/ { exit }
        in_dataset && /^[[:space:]]*data_dir:[[:space:]]*/ {
            sub(/^[[:space:]]*data_dir:[[:space:]]*/, "")
            sub(/[[:space:]]+$/, "")
            print
            exit
        }
    ' "$DATASETS_CONFIG"
}

configured_datasets() {
    awk '
        /^[^[:space:]#][^:]*:[[:space:]]*$/ {
            name = $0
            sub(/:[[:space:]]*$/, "", name)
            print name
        }
    ' "$DATASETS_CONFIG"
}

declare -a datasets=()
if [[ $# -eq 0 ]]; then
    while IFS= read -r dataset; do
        [[ -n "$dataset" ]] && datasets+=("$dataset")
    done < <(configured_datasets)
else
    datasets=("$@")
fi

if [[ ${#datasets[@]} -eq 0 ]]; then
    echo "No datasets were provided" >&2
    exit 2
fi

missing=0
for dataset in "${datasets[@]}"; do
    data_dir=$(dataset_data_dir "$dataset")
    if [[ -z "$data_dir" ]]; then
        echo "Unknown dataset '$dataset' in $DATASETS_CONFIG" >&2
        missing=1
        continue
    fi
    if [[ ! -d "$data_dir" ]]; then
        echo "Dataset directory for $dataset does not exist: $data_dir" >&2
        missing=1
        continue
    fi
    echo "$dataset: $data_dir"
done

exit "$missing"
