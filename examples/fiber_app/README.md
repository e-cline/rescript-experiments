# fiber_app

A todo app written with [`@e-cline/fiber`](../../packages/fiber) and
[`@e-cline/fiber_dom`](../../packages/fiber_dom), bundled by Vite. It uses most of the library:

- the todos in `useReducerWithMapState`, loaded from `localStorage` and saved back by a `useEffect`;
- the current filter passed to the list through `Context`, and switched in a `Transition.start`;
- each item wrapped in `Memo.memo`, with the reducer's stable `dispatch`, so toggling one todo
  renders only that one;
- the new-todo input controlled by `useState`, and focused on mount through a `ref` and an effect.

The source is [`src/App.res`](src/App.res) (components) and [`src/Todo.res`](src/Todo.res) (state).
The root `res` task compiles them to `.res.js`, which `index.html` loads like any other module.

Run it:

```bash
pnpm --filter @e-cline/fiber_app_example exec vp run dev
```

[`tests/App_test.res`](tests/App_test.res) drives the app in jsdom the way a user would: typing,
submitting, clicking, and remounting to check that the todos persist.
