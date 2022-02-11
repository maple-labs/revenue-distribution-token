invariant :; ./invariant-test.sh -t invariant
test      :; ./test.sh
test-all  :; ./test.sh && ./invariant-test.sh -t invariant