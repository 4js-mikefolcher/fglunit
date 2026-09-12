#!/usr/bin/env python3
"""Repository checks that need no Genero toolchain.

Run locally with `make checks`, and in CI on a plain runner so the
workflow is not vacuous on machines without a licensed BDL install.

Each check here exists because the corresponding mistake was actually
made in this repository at least once.
"""
import io
import json
import os
import re
import subprocess
import sys

FAILURES = []

print("repository checks")


def check(name):
    def wrap(fn):
        try:
            problems = fn() or []
        except Exception as exc:  # a broken check is a failing check
            problems = ["check raised %s: %s" % (type(exc).__name__, exc)]
        if problems:
            print("  x %s" % name)
            for p in problems:
                print("      %s" % p)
            FAILURES.append(name)
        else:
            print("  v %s" % name)
        return fn
    return wrap


def read(path):
    return io.open(path, encoding="utf-8").read()


@check("fglpkg.json is valid and complete")
def _manifest():
    m = json.loads(read("fglpkg.json"))
    bad = []
    for field in ("name", "version", "description", "license", "repository", "root"):
        if not m.get(field):
            bad.append("missing or empty field: %s" % field)
    if not re.match(r"^\d+\.\d+\.\d+$", str(m.get("version", ""))):
        bad.append("version %r is not x.y.z" % m.get("version"))
    return bad


@check("LICENSE ships inside the package")
def _license_ships():
    # MIT requires the notice to accompany copies; `docs` is what fglpkg
    # puts in the zip alongside the compiled modules.
    m = json.loads(read("fglpkg.json"))
    docs = m.get("docs") or []
    bad = []
    if "LICENSE" not in docs:
        bad.append('fglpkg.json "docs" does not list LICENSE')
    for f in docs:
        if not os.path.exists(f):
            bad.append("docs lists %s, which does not exist" % f)
    return bad


@check("CHANGELOG has an entry for the manifest version")
def _changelog():
    if not os.path.exists("CHANGELOG.md"):
        return ["CHANGELOG.md is missing (fglpkg publish reads it)"]
    version = json.loads(read("fglpkg.json"))["version"]
    if ("[%s]" % version) not in read("CHANGELOG.md"):
        return ["no '## [%s]' section; fglpkg publish would send an empty changelog" % version]
    return []


@check("every documented 4gl program compiles in principle")
def _doc_examples():
    # BDL requires MAIN to precede every FUNCTION. The headline example in
    # both documents once did the opposite and did not compile.
    bad = []
    for doc in ("README.md", "USERGUIDE.md"):
        for i, block in enumerate(re.findall(r"```4gl\n(.*?)```", read(doc), re.S), 1):
            if not re.search(r"(?m)^MAIN\b", block):
                continue
            main_at = re.search(r"(?m)^MAIN\b", block).start()
            fn = re.search(r"(?m)^(?:PUBLIC |PRIVATE )?FUNCTION\b", block)
            if fn and fn.start() < main_at:
                bad.append("%s: 4gl block %d declares a FUNCTION before MAIN" % (doc, i))
    return bad


@check("no non-ASCII inside runtime string literals")
def _ascii_runtime():
    # Comments may say whatever they like; a DISPLAY string reaches a
    # terminal whose encoding we do not control. This repository has
    # already shipped one broken character that way.
    bad = []
    for root, _, files in os.walk("com"):
        for f in sorted(files):
            if not f.endswith(".4gl"):
                continue
            path = os.path.join(root, f)
            for n, line in enumerate(io.open(path, encoding="utf-8"), 1):
                code = line.split("#")[0]
                if '"' in code and any(ord(c) > 127 for c in code):
                    bad.append("%s:%d: %s" % (path, n, line.strip()))
    return bad


@check("shell scripts are syntactically valid")
def _sh_syntax():
    bad = []
    for path in ("tests/integration.sh",):
        if not os.path.exists(path):
            bad.append("%s is missing" % path)
            continue
        r = subprocess.run(["sh", "-n", path], capture_output=True, text=True)
        if r.returncode != 0:
            bad.append("%s: %s" % (path, (r.stdout + r.stderr).strip()))
    return bad


@check("no compiled artifacts are tracked in git")
def _no_binaries():
    r = subprocess.run(["git", "ls-files"], capture_output=True, text=True)
    return ["tracked build artifact: %s" % f
            for f in r.stdout.split("\n") if re.search(r"\.42[mrf]$", f)]


if __name__ == "__main__":
    # Each @check ran as it was defined, so results are already printed.
    print()
    if FAILURES:
        print("FAILED: %s" % ", ".join(FAILURES))
        sys.exit(1)
    print("All repository checks passed")
