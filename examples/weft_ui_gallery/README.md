# weft_ui_gallery

Every [`weft_ui`](../../packages/weft_ui) component, in every variant, on server-rendered pages: for
looking at, and for checking accessibility. Each page is a group of components (layout, text,
surfaces, data, forms, overlays, disclosure, search, actions and status). Each component's section
shows it in its variants: each example is in a frame, with a caption saying what it shows, and the
gist of its code under it.

- The pages are server components ([`src/server`](src/server)), rendering weft_ui's static
  components and its ready-made entrypoints (`TabsEntry`, `DialogEntry`, `DrawerEntry`,
  `PopoverEntry`, `ToastViewport`) directly, as an app's server components would.
- The interactive examples are entrypoints of the gallery's own ([`src/client`](src/client)): the
  forms, the overlays, manual tabs and a combobox.
- The sidebar's links are an entrypoint ([`NavLink`](src/client/NavLink.res)) that navigates in
  place, wearing weft_ui's link recipe (`Link.className()`), which the server gives it as a string.
- **The theme switcher**, in the header ([`ThemeSwitcher`](src/client/ThemeSwitcher.res)), shows
  weft_ui's defaults or a demo app's palette (weft_notes', weft_shop's): each is a class in
  [`src/shared/Theme.res`](src/shared/Theme.res) that sets weft_ui's tokens on the page's outermost
  element. They're all in the one file whose `root` class every page renders, so every page is sent
  them. Picking one puts its class on the element at once, and keeps it in a cookie, so the server
  renders the next page, navigated to or reloaded, in it.

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
place; the busy button is busy, then done; the forms, overlays, tabs and combobox work; and the
theme switcher puts a palette's class on the page.

[`e2e/gallery.e2e.ts`](e2e/gallery.e2e.ts) checks, against the build, what only a browser can, in
Chromium, Firefox and WebKit:

- [axe](https://github.com/dequelabs/axe-core-npm) (WCAG 2.1, A and AA) on every page, on each
  overlay while it's open, and on the pages with the most colour (surfaces, forms, actions) in each
  demo app's palette;
- the overlays: a dialog modal, its focus kept in it and given back; an alert dialog starting on
  Cancel; a drawer's place and size; a popover's and a combobox's place beside their trigger; the
  menu's keys; a tooltip on focus;
- tabs, automatic and manual, the accordion, and the combobox's keys;
- the theme switcher, its theme kept across a navigation and a reload.

Each with nothing in the console. Run them (they need the browsers:
`pnpm --filter @e-cline/weft_ui_gallery_example exec playwright install`):

```bash
pnpm --filter @e-cline/weft_ui_gallery_example exec vp run e2e
```
