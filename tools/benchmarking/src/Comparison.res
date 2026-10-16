/***
Benchmarks several implementations of the same thing operation by operation, and reports them side
by side once everything has run.

`bench` registers one benchmark per implementation with mitata, which measures and prints them as
it does any other. `print` then adds what mitata's own output doesn't have: one table of every
operation, with each implementation's time and how it compares with the fastest, so that how they
stand can be read at a glance rather than pieced together from each group's summary.
*/

type row = {operation: string, parameter: string}

type t = {implementations: array<string>, rows: array<row>}

/**
A comparison of `implementations`, named as they should appear in output and in this order in its
table.
*/
let make = (~implementations: array<string>): t => {implementations, rows: []}

let benchName = (implementation: string, {operation, parameter}: row): string =>
  `${implementation}.${operation} ${parameter}`

/**
Registers a benchmark of `operation` for each of `implementations`: a name from the comparison's
own, and a setup that builds that implementation's input and returns what to measure, as for
`Mitata.benchWithSetup`. An implementation with no equivalent of the operation is left out.

`parameter` says what distinguishes this operation's benchmarks from others of the same operation
(`"n=1000"`), and is part of each benchmark's name: `"BTree.get n=1000"`, `"Belt.Map.get n=1000"`.
*/
let bench = (
  comparison: t,
  ~operation: string,
  ~parameter: string,
  implementations: array<(string, unit => Mitata.prepared)>,
): unit => {
  let row = {operation, parameter}
  Array.push(comparison.rows, row)
  Mitata.group(`${operation} ${parameter}`, () =>
    Mitata.summary(() =>
      implementations->Array.forEach(
        ((implementation, setup)) =>
          Mitata.benchWithSetup(benchName(implementation, row), setup)->ignore,
      )
    )
  )
}

let formatTime = (nanoseconds: float): string =>
  if nanoseconds < 1e3 {
    `${Float.toFixed(nanoseconds, ~digits=2)} ns`
  } else if nanoseconds < 1e6 {
    `${Float.toFixed(nanoseconds /. 1e3, ~digits=2)} µs`
  } else if nanoseconds < 1e9 {
    `${Float.toFixed(nanoseconds /. 1e6, ~digits=2)} ms`
  } else {
    `${Float.toFixed(nanoseconds /. 1e9, ~digits=2)} s`
  }

/**
The table `print` prints, or `None` if `results` has no operation measured for at least two
implementations (a filter can select just one, or none).

Each row is one operation: the average time per call for each implementation, with how many times
the fastest's that is. Rows are grouped by operation, with a blank line between one operation and
the next, and an implementation nothing was measured for has no column.
*/
let report = (comparison: t, results: Mitata.results): option<string> => {
  let averages = Dict.make()
  results.benchmarks->Array.forEach(trial =>
    trial.runs->Array.forEach(run =>
      switch run.stats {
      | Some({avg}) => averages->Dict.set(run.name, avg)
      | None => ()
      }
    )
  )
  let timeOf = (implementation, row) => averages->Dict.get(benchName(implementation, row))

  let measured = comparison.rows->Array.filter(row =>
    comparison.implementations
    ->Array.filter(implementation => timeOf(implementation, row)->Option.isSome)
    ->Array.length >= 2
  )
  let columns =
    comparison.implementations->Array.filter(implementation =>
      measured->Array.some(row => timeOf(implementation, row)->Option.isSome)
    )

  // Rows are registered in whatever order suits the benchmark program -- typically every operation
  // for one parameter, then the next -- but read best with each operation's rows together. The
  // sort is stable, so operations and their parameters keep the order they were first registered
  // in.
  let operations = []
  measured->Array.forEach(row =>
    if !(operations->Array.includes(row.operation)) {
      Array.push(operations, row.operation)
    }
  )
  let byOperation =
    measured->Array.toSorted((a, b) =>
      Int.toFloat(operations->Array.indexOf(a.operation) - operations->Array.indexOf(b.operation))
    )

  let rows = []
  let previousOperation = ref(None)
  byOperation->Array.forEach(row => {
    if (
      previousOperation.contents->Option.isSome && previousOperation.contents != Some(row.operation)
    ) {
      Array.push(rows, columns->Array.map(_ => "")->Array.concat([""]))
    }
    previousOperation := Some(row.operation)
    let fastest = columns->Array.reduce(infinity, (fastest, implementation) =>
      switch timeOf(implementation, row) {
      | Some(time) => Math.min(fastest, time)
      | None => fastest
      }
    )
    Array.push(
      rows,
      [
        `${row.operation} ${row.parameter}`,
        ...columns->Array.map(implementation =>
          switch timeOf(implementation, row) {
          | Some(time) =>
            `${formatTime(time)} ${Float.toFixed(time /. fastest, ~digits=2)->String.padStart(
                7,
                " ",
              )}x`
          | None => ""
          }
        ),
      ],
    )
  })

  if Array.length(rows) == 0 {
    None
  } else {
    let table = [["", ...columns], ...rows]
    let widths = Array.fromInitializer(~length=Array.length(columns) + 1, column =>
      table->Array.reduce(0, (widest, row) =>
        max(widest, String.length(row->Array.get(column)->Option.getOr("")))
      )
    )
    let lines = table->Array.map(row =>
      row
      ->Array.mapWithIndex((cell, column) => {
        let width = Array.getUnsafe(widths, column)
        // Names read down the left edge; times and multiples line up on their units.
        column == 0 ? String.padEnd(cell, width, " ") : String.padStart(cell, width, " ")
      })
      ->Array.join("  ")
      ->String.trimEnd
    )
    Some(
      "Average time per call, and how many times the fastest implementation's that is\n\n" ++
      lines->Array.join("\n"),
    )
  }
}

/** Prints `report`'s table, after a blank line, if there is one. */
let print = (comparison: t, results: Mitata.results): unit =>
  switch report(comparison, results) {
  | Some(table) => Console.log("\n" ++ table)
  | None => ()
  }
