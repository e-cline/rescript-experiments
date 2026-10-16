# @e-cline/res_react_ui_example

A ReScript-authored React component (`src/Greeting.res`), exploring
[`@rescript/react`](https://github.com/rescript-lang/rescript-react) (JSX authoring), CSS Modules
imported from a `.res` file, and a third-party ReScript library from npm
([`rescript-webapi`](https://www.npmjs.com/package/rescript-webapi)).

Notable things this uncovered:

- genType always names its output `*.gen.tsx`, even with no actual JSX in it -- but TypeScript
  requires the `jsx` compiler option to be set for any `.tsx` file regardless of content. `.gen.tsx`
  also refers to the bare global `React` namespace without an `import` statement (relying on
  `@types/react`'s ambient UMD declaration), so `@types/react` needs to be in scope even though
  nothing here writes `import React from 'react'`. Both are handled in this package's own
  `tsconfig.json`.
- `vp pack` bundles the CSS Modules import in `Greeting.res.jsx` out of the box (tsdown's built-in
  Lightning CSS integration -- see `pack.md`'s "CSS Bundling" section), producing
  `dist/Greeting.css` with real, hashed class names. But no emitted JS file imports that CSS as a
  side effect, so **consumers must import it explicitly**
  (`import '@e-cline/res_react_ui_example/Greeting.css'`) -- see `../res_react_app/src/main.tsx`.
  This package's `exports` map also needed an explicit `"./*.css": "./dist/*.css"` entry: the
  existing `"./*"` entry always appends `.js`/`.d.ts` to the matched subpath, so it can't resolve a
  `.css` request on its own. It also blocks `@e-cline/res_react_ui_example/Greeting.res`
  (`"./*.res": null`), since `dist/Greeting.res.js` is genType's raw, untyped input, never the
  intended import.

`tests/greeting.test.tsx` stays written in TypeScript (using `react-dom/server`'s
`renderToStaticMarkup`) rather than being rewritten in ReScript with `rescript-vitest`: that library
binds Vitest's own assertion API, not a React rendering/testing library, and this workspace doesn't
have ReScript bindings for one. Rendering-and-asserting-on-markup is a React Testing Library-shaped
problem, which is out of scope here.

See the repo-root `RESCRIPT.md` for the full writeup.
