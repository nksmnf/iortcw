#!/usr/bin/env python3
"""Derive CMake source lists from SP/Makefile.

The Makefile stays the authority for what goes into a build: it already encodes
every USE_* conditional, and it is what the macOS build uses. Rather than
duplicating ~350 filenames in CMake and letting the two drift, we ask make for
the object lists it would build and map each object path back to its source.

Run with --check to verify the committed file is still current.
"""

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
PRINT_MK = os.path.join(HERE, "print-vars.mk")

# Which source tree we are deriving from. Both trees carry the same Makefile
# variable names (Q3OBJ, Q3ROBJ, ...), so the only thing that changes is where
# we run make and which directory the emitted paths are relative to.
TREE = "SP"


def tree_dir():
    return os.path.join(REPO, TREE)

# Flags describing the iOS configuration. These decide which conditionals the
# Makefile takes, so they must match what CMake actually compiles with.
MAKE_FLAGS = [
    "PLATFORM=darwin",
    "ARCH=arm64",
    "USE_RENDERER_DLOPEN=0",
    "USE_OPENGLES=1",
    "USE_OPENAL=0",
    "USE_CURL=0",
    "USE_MUMBLE=0",
    "USE_VOIP=0",
    "USE_CODEC_VORBIS=1",
    "USE_CODEC_OPUS=0",
    "BUILD_GAME_QVM=0",
    "BUILD_GAME_SO=1",
]

# Object-path prefix -> source directories to search, in priority order.
# The Makefile flattens most vendored libraries into the client/ and renderer/
# object directories, so those buckets have to span them. resolve() reports any
# basename that matches in two directories of a bucket rather than guessing.
CORE_DIRS = ["client", "server", "qcommon", "sdl", "sys", "asm", "null"]

FREETYPE_DIRS = [
    "freetype-2.9/src/base", "freetype-2.9/src/autofit", "freetype-2.9/src/bdf",
    "freetype-2.9/src/bzip2", "freetype-2.9/src/cache",
    "freetype-2.9/src/cff", "freetype-2.9/src/cid", "freetype-2.9/src/gzip",
    "freetype-2.9/src/lzw", "freetype-2.9/src/pcf", "freetype-2.9/src/pfr",
    "freetype-2.9/src/psaux", "freetype-2.9/src/pshinter", "freetype-2.9/src/psnames",
    "freetype-2.9/src/raster", "freetype-2.9/src/sfnt", "freetype-2.9/src/smooth",
    "freetype-2.9/src/truetype", "freetype-2.9/src/type1", "freetype-2.9/src/type42",
    "freetype-2.9/src/winfonts",
]

OPUS_DIRS = ["opus-1.2.1/src", "opus-1.2.1/celt", "opus-1.2.1/silk",
             "opus-1.2.1/silk/float", "opusfile-0.9/src"]

AUDIO_ZLIB_DIRS = ["botlib", "zlib-1.2.11", "libogg-1.3.3/src"]

PREFIX_DIRS = {
    # libvorbis and splines get their own object subdirectories
    "client/vorbis": ["libvorbis-1.3.6/lib"],
    "splines":       ["splines"],
    # zlib, libogg, botlib and opus are flattened into client/
    "client": CORE_DIRS + AUDIO_ZLIB_DIRS + OPUS_DIRS,
    "ded":    CORE_DIRS + AUDIO_ZLIB_DIRS + OPUS_DIRS,
    # jpeg and freetype are flattened into renderer/
    "renderer": ["renderer", "sdl", "qcommon", "jpeg-8c"] + FREETYPE_DIRS,
    "rend2":    ["rend2", "sdl", "qcommon", "jpeg-8c"] + FREETYPE_DIRS,
    "main/game":    ["game", "qcommon"],
    "main/cgame":   ["cgame", "game", "ui", "qcommon"],
    "main/ui":      ["ui", "game", "cgame", "qcommon"],
    "main/qcommon": ["qcommon"],
}

SRC_EXTS = [".c", ".cpp", ".m", ".mm", ".s", ".S"]

# obj -> [candidate sources], filled in by resolve()
AMBIGUOUS = {}


def make_var(name):
    """Ask make to print one variable, resolved under MAKE_FLAGS."""
    cmd = ["make", "-s", "-f", "Makefile", "-f", PRINT_MK,
           "print-" + name] + MAKE_FLAGS
    out = subprocess.run(cmd, cwd=tree_dir(), capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("make failed for %s:\n%s" % (name, out.stderr))
    return out.stdout.split()


def resolve(obj, build_prefix):
    """Map one object path to a source file relative to <tree>/code."""
    rel = obj
    if rel.startswith(build_prefix):
        rel = rel[len(build_prefix):]
    rel = rel.lstrip("/")
    directory, base = os.path.split(rel)
    stem = os.path.splitext(base)[0]

    # Longest matching prefix wins, so "client/opus" beats "client".
    candidates = None
    for prefix in sorted(PREFIX_DIRS, key=len, reverse=True):
        if directory == prefix or directory.startswith(prefix + "/"):
            candidates = PREFIX_DIRS[prefix]
            break
    if candidates is None:
        candidates = [directory]

    hits = []
    for d in candidates:
        for ext in SRC_EXTS:
            path = os.path.join("code", d, stem + ext)
            if os.path.isfile(os.path.join(tree_dir(), path)):
                hits.append(path)
                break
    if not hits:
        return None
    if len(hits) > 1:
        AMBIGUOUS.setdefault(obj, hits)
    return hits[0]


def collect(varname, build_prefix):
    objs = [o for o in make_var(varname) if o.endswith(".o")]
    sources, missing = [], []
    for o in objs:
        s = resolve(o, build_prefix)
        (sources if s else missing).append(s or o)
    return sources, missing


def main():
    global TREE

    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="fail if the generated file is stale")
    ap.add_argument("--tree", choices=["SP", "MP"], default="SP",
                    help="which source tree to derive from (default: SP)")
    ap.add_argument("-o", "--output", default=None)
    args = ap.parse_args()

    TREE = args.tree
    if args.output is None:
        # SP keeps the historical filename so existing includes stay valid.
        name = ("sources.generated.cmake" if TREE == "SP"
                else "sources.generated.mp.cmake")
        args.output = os.path.join(HERE, name)

    build_prefix = "build/release-darwin-arm64"

    groups = [
        ("IORTCW_ENGINE_SOURCES", "Q3OBJ"),
        ("IORTCW_RENDERER_SOURCES", "Q3ROBJ"),
        ("IORTCW_JPEG_SOURCES", "JPGOBJ"),
        ("IORTCW_FREETYPE_SOURCES", "FTOBJ"),
        ("IORTCW_GAME_SOURCES", "Q3GOBJ"),
        ("IORTCW_CGAME_SOURCES", "Q3CGOBJ"),
        ("IORTCW_UI_SOURCES", "Q3UIOBJ"),
    ]

    lines = [
        "# Generated by ios/cmake/extract_sources.py -- do not edit by hand.",
        "# Regenerate with: python3 ios/cmake/extract_sources.py --tree %s" % TREE,
        "# Paths are relative to the %s/ directory." % TREE,
        "",
    ]
    all_missing = {}

    for cmake_var, make_var_name in groups:
        sources, missing = collect(make_var_name, build_prefix)
        if missing:
            all_missing[make_var_name] = missing
        lines.append("set(%s" % cmake_var)
        for s in sources:
            lines.append("    %s" % s)
        lines.append(")")
        lines.append("")
        print("%-26s %3d sources%s" % (
            cmake_var, len(sources),
            "  (%d UNRESOLVED)" % len(missing) if missing else ""))

    text = "\n".join(lines)

    if AMBIGUOUS:
        print("\nAmbiguous basenames (prefix map needs a more specific entry):",
              file=sys.stderr)
        for obj, hits in AMBIGUOUS.items():
            print("  %s -> %s" % (obj, ", ".join(hits)), file=sys.stderr)
        sys.exit(1)

    if all_missing:
        print("\nUnresolved objects:", file=sys.stderr)
        for var, objs in all_missing.items():
            for o in objs:
                print("  %s: %s" % (var, o), file=sys.stderr)
        sys.exit(1)

    if args.check:
        current = open(args.output).read() if os.path.exists(args.output) else ""
        if current != text:
            sys.exit("%s is stale; rerun extract_sources.py" % args.output)
        print("\nup to date")
        return

    with open(args.output, "w") as f:
        f.write(text)
    print("\nwrote %s" % args.output)


if __name__ == "__main__":
    main()
