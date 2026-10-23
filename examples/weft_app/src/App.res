@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/***
A todo app on `weft`: the todos live in a reducer (saved to `localStorage` by an effect), the
current filter reaches the list through context (switching it is a transition), each item is
memoized, and the new-todo input is focused through a ref when the app mounts.
*/

open Weft.Hooks

module Dom = WeftDom.Dom
module Jsx = WeftDom.Jsx

module FilterContext = {
  let context = Weft.Context.make(Todo.All)
  module Provider = {
    let make = Weft.Context.provider(context)
  }
}

module NewTodo = {
  @jsx.component
  let make = (~onAdd: string => unit) => {
    let (title, setTitle) = useState(() => "")
    let input = useRef(Nullable.null)
    useEffect0(() => {
      input.current->Nullable.forEach(Dom.focus)
      None
    })
    let submit = event => {
      Dom.Event.preventDefault(event)
      let trimmed = String.trim(title)
      if trimmed != "" {
        onAdd(trimmed)
        setTitle(_ => "")
      }
    }
    <form id="new-todo-form" onSubmit=submit>
      <input
        id="new-todo"
        ref=input
        placeholder="What needs doing?"
        ariaLabel="New todo"
        value=title
        onInput={event => setTitle(_ => Dom.Event.targetValue(event))}
      />
    </form>
  }
}

module TodoItem = {
  @jsx.component
  let make = Weft.Memo.memo((~todo: Todo.todo, ~dispatch: Todo.action => unit) => {
    let id = Int.toString(todo.id)
    <li id={`todo-${id}`} className={todo.done ? "done" : ""}>
      <input
        id={`toggle-${id}`}
        type_="checkbox"
        checked=todo.done
        onChange={_ => dispatch(Toggle(todo.id))}
      />
      <span> {Jsx.string(todo.title)} </span>
      <button id={`remove-${id}`} ariaLabel="Remove" onClick={_ => dispatch(Remove(todo.id))}>
        {Jsx.string("×")}
      </button>
    </li>
  })
}

module TodoList = {
  @jsx.component
  let make = (~todos: array<Todo.todo>, ~dispatch: Todo.action => unit) => {
    let filter = useContext(FilterContext.context)
    <ul id="todo-list">
      {Todo.visible(todos, filter)
      ->Array.map(todo => <TodoItem key={Int.toString(todo.id)} todo dispatch />)
      ->Jsx.array}
    </ul>
  }
}

module Filters = {
  @jsx.component
  let make = (~filter: Todo.filter, ~setFilter: (Todo.filter => Todo.filter) => unit) =>
    <nav>
      {[Todo.All, Active, Completed]
      ->Array.map(option => {
        let name = Todo.filterName(option)
        <button
          key=name
          id={`filter-${name}`}
          ariaPressed={option == filter ? "true" : "false"}
          onClick={_ => Weft.Transition.start(() => setFilter(_ => option))}
        >
          {Jsx.string(name)}
        </button>
      })
      ->Jsx.array}
    </nav>
}

@jsx.component
let make = (~storageKey: string="weft-todos") => {
  let (todos, dispatch) = useReducerWithMapState(Todo.reducer, storageKey, Todo.Storage.load)
  let (filter, setFilter) = useState(() => Todo.All)
  useEffect2(() => {
    Todo.Storage.save(storageKey, todos)
    None
  }, (storageKey, todos))
  let remaining = todos->Array.filter(todo => !todo.done)->Array.length
  let completed = Array.length(todos) - remaining
  <main>
    <h1> {Jsx.string("todos")} </h1>
    <NewTodo onAdd={title => dispatch(Add(title))} />
    <FilterContext.Provider value=filter>
      <TodoList todos dispatch />
    </FilterContext.Provider>
    <footer>
      <span id="remaining">
        {Jsx.string(`${Int.toString(remaining)} ${remaining == 1 ? "item" : "items"} left`)}
      </span>
      <Filters filter setFilter />
      {completed > 0
        ? <button id="clear-completed" onClick={_ => dispatch(ClearCompleted)}>
            {Jsx.string("Clear completed")}
          </button>
        : Jsx.null}
    </footer>
  </main>
}
