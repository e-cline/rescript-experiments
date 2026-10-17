/***
The todo list's state: the todos, what can happen to them, and keeping them in `localStorage`.
*/

type todo = {id: int, title: string, done: bool}

type filter =
  | All
  | Active
  | Completed

type action =
  | Add(string)
  | Toggle(int)
  | Remove(int)
  | ClearCompleted

let nextId = (todos: array<todo>) =>
  todos->Array.reduce(0, (id, todo) => Math.Int.max(id, todo.id)) + 1

let reducer = (todos: array<todo>, action: action) =>
  switch action {
  | Add(title) => todos->Array.concat([{id: nextId(todos), title, done: false}])
  | Toggle(id) => todos->Array.map(todo => todo.id == id ? {...todo, done: !todo.done} : todo)
  | Remove(id) => todos->Array.filter(todo => todo.id != id)
  | ClearCompleted => todos->Array.filter(todo => !todo.done)
  }

let visible = (todos: array<todo>, filter: filter) =>
  switch filter {
  | All => todos
  | Active => todos->Array.filter(todo => !todo.done)
  | Completed => todos->Array.filter(todo => todo.done)
  }

let filterName = (filter: filter) =>
  switch filter {
  | All => "all"
  | Active => "active"
  | Completed => "completed"
  }

module Storage = {
  @val @scope("localStorage") external getItem: string => Nullable.t<string> = "getItem"
  @val @scope("localStorage") external setItem: (string, string) => unit = "setItem"

  // Records are plain objects at runtime, so the JSON round-trips; anything unreadable starts empty.
  external fromJson: JSON.t => array<todo> = "%identity"

  let load = (key: string): array<todo> =>
    switch Nullable.toOption(getItem(key)) {
    | Some(saved) =>
      try fromJson(JSON.parseOrThrow(saved)) catch {
      | _ => []
      }
    | None => []
    }

  let save = (key: string, todos: array<todo>) =>
    switch JSON.stringifyAny(todos) {
    | Some(json) => setItem(key, json)
    | None => ()
    }
}
