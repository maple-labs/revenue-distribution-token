invariant :; ./invariant-test.sh -t invariant
test      :; ./test.sh -p local
test-all  :; ./test.sh && ./invariant-test.sh -t invariant
