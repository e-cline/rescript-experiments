---
'@e-cline/weft_ui': patch
---

A new package: accessible, styled UI components for Weft, built on `weft_css` and the platform's own
elements (`<dialog>`, the Popover API, CSS anchor positioning, `<details>`, native inputs).

- **Static** components, which a server component can render: Stack, Grid, Container, Separator,
  Heading, Text, Link, VisuallyHidden, Card, Alert, Badge, EmptyState, Table, List, DescriptionList,
  Breadcrumbs, Steps, Spinner, Skeleton, Button, IconButton, Collapsible and Accordion.
- **Interactive** ones, controlled or keeping their own state: Form, Field, Fieldset, Input,
  Textarea, Select, Checkbox, RadioGroup, Switch, NumberField, Toggle, ToggleGroup, Dialog,
  AlertDialog, Drawer, Popover, Menu, Tooltip, Toast, Tabs and Combobox, following the ARIA
  Authoring Practices' patterns.
- **Ready-made entrypoints** for server components: `TabsEntry`, `DialogEntry`, `DrawerEntry`,
  `PopoverEntry` and `ToastViewport`.

Each is restyled through theme tokens (`Tokens`, CSS variables whose defaults any app value
overrides), variant props, `className` (in the cascade layer `weft.components.ui`, under an app's
own classes), state attributes and `style`; each styled component's classes are also a function (a
recipe) for something else to wear. `attrs` passes any other DOM prop to a part.
`Testing.installJsdomShims()` gives jsdom enough of `<dialog>` and the Popover API for the overlays
to work in tests.
