invariant       :; ./invariant-test.sh -t invariant
test            :; ./test.sh -p local
deep-test       :; ./test.sh -p deep
test-all        :; ./test.sh && ./invariant-test.sh -t invariant
forge-invariant :; ./invariant-forge-test.sh
