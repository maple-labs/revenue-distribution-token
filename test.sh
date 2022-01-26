#!/usr/bin/env bash
set -e

while getopts t:r:b:v:c: flag
do
    case "${flag}" in
        t) test=${OPTARG};;
        r) runs=${OPTARG};;
    esac
done

runs=$([ -z "$runs" ] && echo "10" || echo "$runs")

export DAPP_SOLC_VERSION=0.8.7
export PROPTEST_CASES=$runs

if [ -z "$test" ]; then match="[src/test/*.t.sol]"; else match=$test; fi

forge test --match "$match" -vvv