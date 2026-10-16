#!/usr/bin/env sh
# Makes sure the OCaml toolchain the PPX builds with is in place: an opam
# switch local to this directory (`_opam/`, gitignored), holding exactly the
# compiler and package versions pinned in `ppx_pretty_print.opam.locked`.
#
# Run by the `build` task before dune (see vite.config.ts), so a fresh clone
# needs nothing but opam itself installed. Creating the switch compiles OCaml
# and takes a few minutes; after that this is a no-op until the lock file
# changes.

set -e
cd "$(dirname "$0")"

LOCK=ppx_pretty_print.opam.locked
# Touched after each successful install, to tell when the lock file has
# changed since.
STAMP=_opam/.ppx_pretty_print_deps

if ! command -v opam >/dev/null 2>&1; then
  echo "ppx_pretty_print: opam not found -- install it (https://opam.ocaml.org/doc/Install.html) and run \`opam init\`" >&2
  exit 1
fi

if [ ! -d _opam ]; then
  echo "ppx_pretty_print: creating the local opam switch (compiles OCaml; takes a few minutes)..."
  opam switch create . --deps-only --locked --yes
  touch "$STAMP"
elif [ ! -e "$STAMP" ] || [ "$LOCK" -nt "$STAMP" ]; then
  echo "ppx_pretty_print: updating the local opam switch to match $LOCK..."
  opam install . --deps-only --locked --yes --switch=.
  touch "$STAMP"
fi
