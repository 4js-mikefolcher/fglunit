#!/bin/sh
# Integration checks for fglunit behaviour that a suite cannot assert
# about itself: process exit codes, --list, empty runs and fixture
# ordering. Driven by `make -C tests`; expects fixture_Lifecycle.42m to
# be compiled already.

set -u
FIX=./fixture_Lifecycle.42m
FAILED=0

# the fixture is a .42m, so it runs through fglrun
fixture() { fglrun "$FIX" --color never "$@"; }

pass() { printf '  v %s\n' "$1"; }
fail() { printf '  x %s\n      %s\n' "$1" "$2"; FAILED=1; }

# exit_is <desc> <want> <args...>
exit_is() {
    desc=$1; want=$2; shift 2
    fixture "$@" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then pass "$desc"; else fail "$desc" "exit $got, wanted $want"; fi
}

# says <desc> <pattern> <args...>
says() {
    desc=$1; pat=$2; shift 2
    if fixture "$@" 2>&1 | grep -q -- "$pat"; then
        pass "$desc"
    else
        fail "$desc" "output did not contain: $pat"
    fi
}

# lines_are <desc> <want> <args...>
lines_are() {
    desc=$1; want=$2; shift 2
    got=$(fixture "$@" 2>&1 | grep -c .)
    if [ "$got" -eq "$want" ]; then pass "$desc"; else fail "$desc" "$got lines, wanted $want"; fi
}

echo "integration"

exit_is  "a suite with failures exits 1"                1
exit_is  "a suite filtered down to passes exits 0"      0 --filter alpha
says     "the filter actually narrows the run"          "Tests: 1"  --filter alpha

# --list
lines_are "--list prints every registered test"         6 --list
lines_are "--list honours --filter"                     1 --list --filter beta
exit_is   "--list exits 0"                              0 --list

# empty runs must not report success
exit_is  "a filter matching nothing exits 1"            1 --filter no_such_test
says     "and says why"      "matched none of the 6"      --filter no_such_test
exit_is  "--allow-empty opts back out"                  0 --filter no_such_test --allow-empty

# lifecycle
says "tearDown runs after an erroring test"  "FIXTURES setUp=6 tearDown=5"
says "an erroring test reports E"            "E gamma_errors"
says "a plain skip reports SKIP"             "- delta_skips"
says "a failure outranks a skip"             "x epsilon_skip_then_fails"

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "Integration: all checks passed"
else
    echo ""
    echo "Integration: FAILURES"
fi
exit $FAILED
