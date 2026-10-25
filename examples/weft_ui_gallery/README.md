# weft_ui_gallery

Every [`weft_ui`](../../packages/weft_ui) component, in every variant, on server-rendered pages: for
looking at, and for checking accessibility. Each page is a group of components (layout, text,
surfaces, data, actions and status), and each component's section shows it in its variants, each
example in a frame with a caption saying what it shows.

- The pages are server components ([`src/server`](src/server)), rendering weft_ui's static
  components directly, as an app's server components would. The sidebar's links are an entrypoint
  ([`NavLink`](src/client/NavLink.res)) that navigates in place, wearing weft_ui's link recipe
  (`Link.className()`), which the server gives it as a string.
- The interactive examples are entrypoints of the gallery's own (`SaveDemo`: a button busy for a
  moment).
- Its look is weft_ui's defaults: [`src/shared/Theme.res`](src/shared/Theme.res) only sets the
  page's font and colours from the library's tokens.

More groups (forms, overlays, disclosure, search) arrive with the plan's later phases
([docs/weft_ui_plan.md](../../docs/weft_ui_plan.md)), each in the phase that builds its components,
and a theme switcher showing each demo app's palette.

Run it:

```bash
pnpm --filter @e-cline/weft_ui_gallery_example exec vp run dev
```

or build it and serve the build:

```bash
pnpm --filter @e-cline/weft_ui_gallery_example exec vp run start
```

## Tests

[`tests/Gallery_test.res`](tests/Gallery_test.res) opens every page through the plugin's harness
(the server in a worker, the pages in jsdom): each renders, hydrates over the server's HTML with
nothing rendered again, and shows nothing before its stylesheet has loaded; the sidebar navigates in
place; and the busy button is busy, then done.
