#!/usr/bin/env sh
# Makes sure the OCaml toolchain the PPX builds with is in place: a global
# opam switch named `ppx_pretty_print` (under ~/.opam, or wherever OPAMROOT
# points), holding exactly the compiler and package versions pinned in
# `ppx_pretty_print.opam.locked`.
#
# Run by the `build` task before dune (see vite.config.ts), so a fresh clone
# needs nothing but opam itself installed. Creating the switch compiles OCaml
# and takes a few minutes; after that this is a no-op until the lock file
# changes. The switch lives outside the checkout, so every clone and git
# worktree on the machine shares it -- a new worktree builds without
# compiling OCaml again.
#
# Sharing it has one cost: checkouts with *different* lock files fight over
# it. Each build re-syncs the switch to its own lock file, which is quick for
# a package bump but recompiles everything when the OCaml version differs.

set -e
cd "$(dirname "$0")"

SWITCH=ppx_pretty_print
LOCK=ppx_pretty_print.opam.locked

if ! command -v opam >/dev/null 2>&1; then
  echo "ppx_pretty_print: opam not found -- install it (https://opam.ocaml.org/doc/Install.html) and run \`opam init\`" >&2
  exit 1
fi

if ! opam switch list --short 2>/dev/null | grep -qx "$SWITCH"; then
  echo "ppx_pretty_print: creating the opam switch \`$SWITCH\` (compiles OCaml; takes a few minutes)..."
  # Empty -- no compiler invariant -- so a lock file change can move it to
  # another OCaml version. `--no-switch` leaves the user's current switch
  # alone.
  opam switch create "$SWITCH" --empty --no-switch --yes \
    --description="tools/ppx/pretty_print's toolchain, managed by its setup.sh"
fi

# A copy of the lock file the switch was last brought in sync with, written
# after each successful install. Kept inside the switch rather than the
# checkout, since the switch is what it describes; and compared by content
# rather than modification time, since a fresh worktree's files are all new.
STAMP="$(opam var prefix --switch="$SWITCH")/.ppx_pretty_print.opam.locked"

if ! cmp -s "$LOCK" "$STAMP"; then
  echo "ppx_pretty_print: installing $LOCK into the opam switch \`$SWITCH\`..."
  opam install . --deps-only --locked --yes --switch="$SWITCH"
  cp "$LOCK" "$STAMP"
fi
