/***
The entry point every benchmark program ends with, so they all take the same command-line
arguments.
*/

@val external argv: array<string> = "process.argv"

/**
Runs every registered benchmark. If the program was given an argument, it is a regular expression
and only the benchmarks whose name matches it run: `node dist/bench.js "^get"`.
*/
let main = (): promise<Mitata.results> =>
  switch argv[2] {
  | Some(pattern) => Mitata.run(~options={filter: RegExp.fromString(pattern)})
  | None => Mitata.run()
  }
