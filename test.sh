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

if [ -z "$test" ]; then match="[src/test/*.t.sol]"; else match=$test; fi

echo Using profile: $FOUNDRY_PROFILE

rm -rf out

forge test --match "$test"
