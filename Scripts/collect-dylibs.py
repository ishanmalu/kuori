#!/usr/bin/env python3
"""Deterministic replacement for dylibbundler.

Walks `otool -L` from each binary in Resources/engine/, copies every non-system
dylib into Resources/engine/libs/, and rewrites install names so the tree loads
from @loader_path with no absolute Homebrew paths. Re-signs ad-hoc at the end.

Usage: Scripts/collect-dylibs.py [engine_dir]   (default: Resources/engine)
"""
import glob
import os
import shutil
import subprocess
import sys

ENGINE = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "Resources/engine")
LIBS = os.path.join(ENGINE, "libs")
SYSTEM_PREFIXES = ("/usr/lib/", "/System/")
BREW_PREFIXES = ("/opt/homebrew/", "/usr/local/")
RPATH_SEARCH = (
    ["/opt/homebrew/lib", "/usr/local/lib"]
    + glob.glob("/opt/homebrew/opt/*/lib")
    + glob.glob("/opt/homebrew/Cellar/*/*/lib")
)


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True, check=False)


def otool_deps(path):
    out = sh("otool", "-L", path).stdout.splitlines()
    deps = []
    for line in out[1:]:                       # line 0 is the file / its own id
        line = line.strip()
        if not line or "(compatibility" not in line:
            continue
        deps.append(line.split(" (")[0])
    return deps


def resolve(dep):
    """Source file for a dependency string, or None to leave it alone.

    The dylib is stored under the *basename of the load command* (e.g.
    liblz4.1.dylib), not the fully-versioned realpath name, so the later
    install_name_tool -change lookups match.
    """
    if dep.startswith(SYSTEM_PREFIXES):
        return None
    base = os.path.basename(dep)
    if dep.startswith(BREW_PREFIXES):
        return dep if os.path.exists(dep) else None
    if dep.startswith(("@rpath/", "@loader_path/", "@executable_path/")):
        if os.path.exists(os.path.join(LIBS, base)):
            return None
        for d in RPATH_SEARCH:
            cand = os.path.join(d, base)
            if os.path.exists(cand):
                return cand
    return None


def main():
    os.makedirs(LIBS, exist_ok=True)
    roots = [
        os.path.join(ENGINE, f)
        for f in os.listdir(ENGINE)
        if os.path.isfile(os.path.join(ENGINE, f)) and os.access(os.path.join(ENGINE, f), os.X_OK)
    ]
    print(f"roots: {', '.join(sorted(os.path.basename(r) for r in roots))}")

    # BFS: copy every reachable non-system dylib into LIBS.
    queue = list(roots)
    vendored = {}                              # basename -> abs path in LIBS
    for f in os.listdir(LIBS):
        if f.endswith(".dylib"):
            vendored[f] = os.path.join(LIBS, f)

    while queue:
        path = queue.pop()
        for dep in otool_deps(path):
            src = resolve(dep)
            if not src:
                continue
            base = os.path.basename(dep)              # store under the load-command name
            if base in vendored:
                continue
            dst = os.path.join(LIBS, base)
            shutil.copy(os.path.realpath(src), dst)   # follow the symlink for the bytes
            os.chmod(dst, 0o755)
            vendored[base] = dst
            queue.append(dst)
    print(f"vendored {len(vendored)} dylibs")

    def rpaths(path):
        out = sh("otool", "-l", path).stdout.splitlines()
        found, res = False, []
        for line in out:
            s = line.strip()
            if s.startswith("cmd LC_RPATH"):
                found = True
            elif found and s.startswith("path "):
                res.append(s.split("path ", 1)[1].split(" (offset")[0])
                found = False
        return res

    # Rewrite install names everywhere.
    def rewrite(path, is_root):
        os.chmod(path, 0o755)
        if not is_root:
            sh("install_name_tool", "-id", f"@loader_path/{os.path.basename(path)}", path)
        for dep in otool_deps(path):
            base = os.path.basename(dep)
            if base not in vendored:
                continue
            new = f"@loader_path/libs/{base}" if is_root else f"@loader_path/{base}"
            if dep != new:
                sh("install_name_tool", "-change", dep, new, path)
        # Drop any rpath that points back into a package manager tree.
        for rp in rpaths(path):
            if rp.startswith(BREW_PREFIXES):
                sh("install_name_tool", "-delete_rpath", rp, path)

    for r in roots:
        rewrite(r, True)
    for lib in vendored.values():
        rewrite(lib, False)

    # Re-sign ad-hoc (install_name_tool invalidated signatures).
    for lib in vendored.values():
        sh("codesign", "--force", "--sign", "-", lib)
    for r in roots:
        sh("codesign", "--force", "--sign", "-", r)

    # Verify: nothing should still point at an absolute brew path.
    bad = []
    for path in roots + list(vendored.values()):
        for dep in otool_deps(path):
            if dep.startswith(BREW_PREFIXES):
                bad.append((os.path.basename(path), dep))
    if bad:
        print("LEAKS:")
        for who, dep in bad:
            print(f"  {who}  ->  {dep}")
        sys.exit(1)
    print("clean — no absolute Homebrew paths remain")


if __name__ == "__main__":
    main()
