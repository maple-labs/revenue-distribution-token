#!/usr/bin/env bash
set -e

while getopts p:t: flag
do
    case "${flag}" in
        p) profile=${OPTARG};;
        t) test=${OPTARG};;
    esac
done

export FOUNDRY_PROFILE=$profile

echo Using profile: $FOUNDRY_PROFILE

../foundry/target/debug/forge test --match "invariant_rdt_totalAssets_lte_underlyingBalance" --lib-paths "modules";
