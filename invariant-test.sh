# #!/usr/bin/env bash
# set -e

# while getopts t:r:d flag
# do
#     case "${flag}" in
#         t) test=${OPTARG};;
#         r) runs=${OPTARG};;
#         d) depth=${OPTARG};;
#     esac
# done

# runs=$([ -z "$runs" ] && echo "1" || echo "$runs")
# depth=$([ -z "$depth" ] && echo "200" || echo "$depth")

# export DAPP_SOLC_VERSION=0.8.7

# export DAPP_SRC="contracts"
# export DAPP_LIB="modules"
# export DAPP_TEST_TIMESTAMP="1652117293"

# if [ -z "$test" ]; then match="[src/test/*.t.sol]"; else match=$test; fi

# # Necessary until forge adds invariant testing support
# rm -rf out
# dapp test --match "$match" --fuzz-runs $runs --depth $depth --verbosity 2

../foundry/target/release/forge test --match-test invariant
