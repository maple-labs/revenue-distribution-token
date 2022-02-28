#!/usr/bin/env bash
set -e

while getopts p:m: flag
do
    case "${flag}" in
        p) profile=${OPTARG};;
        m) match=${OPTARG};;
    esac
done

export FOUNDRY_PROFILE=$profile

if [ -z "$test" ]; then match="[src/test/*.t.sol]"; else match=$test; fi

echo Using profile: $FOUNDRY_PROFILE

forge test --match "$match" -vvv