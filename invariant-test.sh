#!/usr/bin/env bash
set -e

while getopts t:r:d flag
do
    case "${flag}" in
        t) test=${OPTARG};;
        r) runs=${OPTARG};;
        d) depth=${OPTARG};;
    esac
done

runs=$([ -z "$runs" ] && echo "1" || echo "$runs")
depth=$([ -z "$depth" ] && echo "500" || echo "$depth")

export DAPP_SOLC_VERSION=0.8.7

if [ -z "$test" ]; then match="[src/test/*.t.sol]"; else match=$test; fi

# Necessary until forge adds invariant testing support
rm -rf out
dapp test --match "$match" --fuzz-runs $runs --depth $depth --verbosity 3
