/***
The bits of Node these tests need: reading files, and running the compiler.
*/

@module("node:fs") external readFileSync: (string, @as("utf8") _) => string = "readFileSync"
@module("node:fs") external readdirSync: string => array<string> = "readdirSync"
@module("node:fs") external writeFileSync: (string, string) => unit = "writeFileSync"
@module("node:fs") external mkdtempSync: string => string = "mkdtempSync"
@module("node:os") external tmpdir: unit => string = "tmpdir"
@module("node:path") external join: (string, string) => string = "join"
@module("node:path") external dirname: string => string = "dirname"
@module("node:url") external fileURLToPath: string => string = "fileURLToPath"

/** This package's directory (`tools/ppx/weft_tests`): the parent of `specs/`, where this file is. */
let packageRoot = dirname(dirname(fileURLToPath(%raw(`import.meta.url`))))

/** `timeout` is in milliseconds: the child is killed after it. */
type spawnOptions = {cwd: string, encoding: string, timeout: int}
type spawnResult = {status: Nullable.t<int>, stdout: string, stderr: string}

@module("node:child_process")
external spawnSync: (string, array<string>, spawnOptions) => spawnResult = "spawnSync"
