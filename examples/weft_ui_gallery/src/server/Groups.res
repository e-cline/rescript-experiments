@@weft.server

/*** The gallery's pages: one per group of components, in the order the sidebar lists them. */

type group = {slug: string, title: string, summary: string, components: array<string>}

let all = [
  {
    slug: "layout",
    title: "Layout",
    summary: "Putting things in columns, rows and grids, a gap apart.",
    components: ["Stack", "Grid", "Container", "Separator"],
  },
  {
    slug: "text",
    title: "Text",
    summary: "Headings, text in tones and sizes, links, and text only assistive technology reads.",
    components: ["Heading", "Text", "Link", "VisuallyHidden"],
  },
  {
    slug: "surfaces",
    title: "Surfaces",
    summary: "Cards, alerts, badges, and what to show when there's nothing.",
    components: ["Card", "Alert", "Badge", "EmptyState"],
  },
  {
    slug: "data",
    title: "Data",
    summary: "Tables, lists, terms and their details, breadcrumbs and steps.",
    components: ["Table", "List", "DescriptionList", "Breadcrumbs", "Steps"],
  },
  {
    slug: "forms",
    title: "Forms",
    summary: "Fields, text inputs, selects, checkboxes, radio buttons, switches, number fields and toggles.",
    components: [
      "Form",
      "Field",
      "Fieldset",
      "Input",
      "Textarea",
      "Select",
      "Checkbox",
      "RadioGroup",
      "Switch",
      "NumberField",
      "Toggle",
      "ToggleGroup",
    ],
  },
  {
    slug: "overlays",
    title: "Overlays",
    summary: "Dialogs, alert dialogs, drawers, popovers, menus, tooltips and toasts.",
    components: ["Dialog", "AlertDialog", "Drawer", "Popover", "Menu", "Tooltip", "Toast"],
  },
  {
    slug: "actions",
    title: "Actions and status",
    summary: "Buttons, icon buttons, and saying something's working.",
    components: ["Button", "IconButton", "Spinner", "Skeleton"],
  },
]

let find = slug => all->Array.find(group => group.slug == slug)
