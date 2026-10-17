# res_fiber_app

A todo app written with [`@e-cline/res_fiber`](../../packages/res_fiber) and
[`@e-cline/res_fiber_dom`](../../packages/res_fiber_dom), bundled by Vite. It uses most of the
library:

- the todos in `useReducerWithMapState`, loaded from `localStorage` and saved back by a `useEffect`;
- the current filter passed to the list through `Context`;
- each item wrapped in `Memo.memo`, with the reducer's stable `dispatch`, so toggling one todo
  renders only that one;
- the new-todo input controlled by `useState`, and focused on mount through a `ref` and an effect.

The source is [`src/App.res`](src/App.res) (components) and [`src/Todo.res`](src/Todo.res) (state).
The root `res` task compiles them to `.res.jsx`, which `index.html` loads like any other module.

Run it:

```bash
pnpm --filter @e-cline/res_fiber_app_example exec vp run dev
```

[`tests/App_test.res`](tests/App_test.res) drives the app in jsdom the way a user would: typing,
submitting, clicking, and remounting to check that the todos persist.
