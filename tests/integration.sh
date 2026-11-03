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

# CliArgs — argument handling is process-level, so it can only be
# exercised from outside the suite.
raw_exit_is() {
    desc=$1; want=$2; shift 2
    fglrun "$FIX" "$@" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then pass "$desc"; else fail "$desc" "exit $got, wanted $want"; fi
}
raw_exit_is "--help exits 0"                      0 --help
raw_exit_is "-h exits 0"                          0 -h
raw_exit_is "an unknown option exits 2"           2 --no-such-flag
raw_exit_is "an invalid --color value exits 2"    2 --color bogus
raw_exit_is "--junit without a value exits 2"     2 --junit
raw_exit_is "--filter without a value exits 2"    2 --filter

# lifecycle
says "tearDown runs after an erroring test"  "FIXTURES setUp=6 tearDown=5"
says "an erroring test reports E"            "E gamma_errors"
says "a plain skip reports SKIP"             "- delta_skips"
says "a failure outranks a skip"             "x epsilon_skip_then_fails"

# cases and fuzz targets. fixture_Fuzz is deliberately not green: okFuzz
# holds, badFuzz fails an assertion, errFuzz raises, badCases has one bad
# row and noCases has none.
FUZZFIX=./fixture_Fuzz.42m
fuzzfix() { fglrun "$FUZZFIX" --color never "$@"; }

fuzz_exit_is() {
    desc=$1; want=$2; shift 2
    fuzzfix "$@" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then pass "$desc"; else fail "$desc" "exit $got, wanted $want"; fi
}

fuzz_says() {
    desc=$1; pat=$2; shift 2
    if fuzzfix "$@" 2>&1 | grep -q -- "$pat"; then
        pass "$desc"
    else
        fail "$desc" "output did not contain: $pat"
    fi
}

fuzz_exit_is "a fuzz target that holds exits 0"               0 --filter okFuzz
fuzz_exit_is "a fuzz target that fails exits 1"               1 --filter badFuzz
fuzz_says    "a fuzz run prints its seed"        "fuzz seed 42"  --filter okFuzz --seed 42
fuzz_says    "a failure says how to replay it"   "replay: --filter badFuzz --seed"  --filter badFuzz
fuzz_says    "a failure shows the inputs"        "inputs: str="  --filter badFuzz
fuzz_says    "a failure is shrunk"               "(shrunk from 100)"  --filter badFuzz
fuzz_says    "a runtime error in a target is E"  "E errFuzz"     --filter errFuzz
fuzz_says    "the error shrinks to the smallest input"  "size:   0"  --filter errFuzz
fuzz_says    "--fuzz-runs 0 skips fuzz targets"  "fuzzing disabled"  --filter okFuzz --fuzz-runs 0 -v
fuzz_says    "--fuzz-size replays without shrinking again"  "size:   20$"  --filter badFuzz --seed 5 --fuzz-size 20 --fuzz-runs 200
fuzz_exit_is "a run with every fuzz target skipped exits 0"   0 --filter okFuzz --fuzz-runs 0

# The same seed gives the same failure, and the replay options reproduce
# exactly the shrunk failure the first run reported.
first=$(fuzzfix --filter badFuzz --seed 5 2>&1)
second=$(fuzzfix --filter badFuzz --seed 5 2>&1)
first_in=$(printf '%s\n' "$first" | grep 'inputs:')
second_in=$(printf '%s\n' "$second" | grep 'inputs:')
if [ -n "$first_in" ] && [ "$first_in" = "$second_in" ]; then
    pass "the same --seed reproduces the same failing input"
else
    fail "the same --seed reproduces the same failing input" "'$first_in' vs '$second_in'"
fi
fseed=$(printf '%s\n' "$first" | sed -n 's/^ *seed: *\([0-9]*\).*/\1/p')
fsize=$(printf '%s\n' "$first" | sed -n 's/^ *size: *\([0-9]*\).*/\1/p')
replay=$(fuzzfix --filter badFuzz --seed "$fseed" --fuzz-size "$fsize" --fuzz-runs 1 2>&1)
replay_rc=$?
replay_in=$(printf '%s\n' "$replay" | grep 'inputs:')
if [ "$replay_rc" -eq 1 ] && [ "$replay_in" = "$first_in" ]; then
    pass "the replay options reproduce the shrunk failure"
else
    fail "the replay options reproduce the shrunk failure" \
        "exit $replay_rc, inputs '$replay_in' vs '$first_in' (seed '$fseed' size '$fsize')"
fi

fuzz_exit_is "cases that all pass exit 0"                     0 --filter okCases
fuzz_says    "each row is its own test"          "Tests: 2"      --filter okCases
fuzz_exit_is "a failing row exits 1"                          1 --filter badCases
fuzz_says    "and only that row fails"           "Failed: 1"     --filter badCases
fuzz_says    "a failing row names itself"        'case {"a":2,"b":2,"expected":5}'  --filter badCases
fuzz_exit_is "an empty case table fails the run"              1 --filter noCases
fuzz_says    "and says so"                       "table has no rows"  --filter noCases
lines=$(fuzzfix --list --filter Cases 2>&1 | grep -c .)
if [ "$lines" -eq 6 ]; then pass "--list expands every case"; else fail "--list expands every case" "$lines lines, wanted 6"; fi

# fglunit-run forwards the fuzz options to its children.
runner=../com/fourjs/fglunit/fglunit_run.42m
if fglrun "$runner" -v --seed 5 --fuzz-runs 3 --filter okFuzz "$FUZZFIX" 2>&1 | grep -q "fuzz seed 5"; then
    pass "fglunit-run forwards --seed to each suite"
else
    fail "fglunit-run forwards --seed to each suite" "child did not report seed 5"
fi
fglrun "$runner" --seed 'x;id' "$FUZZFIX" >/dev/null 2>&1
if [ $? -eq 2 ]; then pass "fglunit-run refuses a non-numeric --seed"; else fail "fglunit-run refuses a non-numeric --seed" "did not exit 2"; fi

fuzz_exit_is "--seed with a non-number exits 2"               2 --seed abc
fuzz_exit_is "--seed without a value exits 2"                 2 --seed
fuzz_exit_is "--fuzz-runs with a negative number exits 2"     2 --fuzz-runs -1
fuzz_exit_is "--fuzz-size with a non-number exits 2"          2 --fuzz-size big

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "Integration: all checks passed"
else
    echo ""
    echo "Integration: FAILURES"
fi
exit $FAILED
