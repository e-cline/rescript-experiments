---
'@e-cline/weft_dom': patch
---

What accessible widgets need: `DomProps` gains the ARIA attributes for forms, popups, composite
widgets, ranges and live regions (`ariaInvalid`, `ariaHaspopup`, `ariaActivedescendant`,
`ariaValuenow`, ...), data attributes for a component's state (`dataState`, `dataOrientation`,
`dataHighlighted`, `dataSide`, `dataVariant`), `inert`, `open_`, the Popover API's `popover`,
`popoverTarget` and `popoverTargetAction`, the table and form attributes `rowSpan`, `scope`,
`headers`, `minLength`, `pattern`, `multiple`, `size`, `form` and `noValidate`, `lang` and `dir`,
and the `onFocusIn`/`onFocusOut`, pointer, `onToggle`/`onBeforeToggle` and `onClose`/`onCancel`
events. `Dom` gains `contains`, `matches`, `closest`, `parentElement`, `blur`, `scrollIntoView`,
`getBoundingClientRect`, document listeners, `Dialog` (`showModal`, `show`, `close`, `isOpen`),
`Popover` (`show`, `hide`, `toggle`), and `Event`'s `stopPropagation`, `defaultPrevented`, modifier
keys, `relatedTarget` and `newState`.
