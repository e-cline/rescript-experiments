(* The standalone executable `rescript.json`'s `ppx-flags` points at (through
   the `../../ppx` wrapper script). bsc invokes it as `main.exe <input> <output>`,
   where both files are binary-marshalled ASTs; ppxlib's driver handles that
   protocol and runs every transformation registered by a linked library --
   here, just the one in `../ppx_pretty_print.ml`. *)
let () = Ppxlib.Driver.run_as_ppx_rewriter ()
