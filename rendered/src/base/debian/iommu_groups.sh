#!/bin/bash
# Display the IOMMU Groups the PCI devices are assigned to.
# Usage:
#   src/base/debian/iommu_groups.sh

# shellcheck source=src/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../base/lib.sh"

shopt -s nullglob

for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
    echo "IOMMU Group ${g##*/}:"
    for d in "$g"/devices/*; do
        echo -e "\t$(lspci -nns "${d##*/}")"
    done;
done;
