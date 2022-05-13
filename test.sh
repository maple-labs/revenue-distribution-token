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

if [ -z "$test" ];
then
    forge test --match-path "contracts/test/*" --gas-report;
else
    forge test --match "$test" --gas-report;
    # ../foundry/target/debug/forge test --match "$test" --gase
fi
