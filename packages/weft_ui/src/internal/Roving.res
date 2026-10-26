/***
Arrow-key focus in a group (a toggle group, later tabs and menus): the arrow keys along the group's
orientation move the focus to the previous or next item, wrapping round, and Home and End to the
first and last. Only items that aren't disabled count. Items are found in the DOM, by a class each
has, inside the nearest element with the group's class.
*/

module Dom = WeftDom.Dom

/** The enabled items of the group `item` is in, in document order. */
let items = (item: Dom.element, ~group: string, ~item as itemClass: string) =>
  switch Dom.closest(item, `.${group}`)->Nullable.toOption {
  | Some(root) =>
    root
    ->Dom.querySelectorAll(`.${itemClass}`)
    ->Array.filter(element => !Dom.matches(element, ":disabled, [aria-disabled=\"true\"]"))
  | None => []
  }

/**
Handles `event`, a key press on an item, if it's one that moves the focus: focuses the item it
moves to and returns it (`None` for any other key).
*/
let onKeyDown = (event, ~group, ~item, ~orientation: Variants.orientation) => {
  let current = Dom.Event.currentTarget(event)
  let all = items(current, ~group, ~item)
  let count = Array.length(all)
  let index = all->Array.findIndex(element => element === current)
  let (previous, next) =
    orientation == #vertical ? ("ArrowUp", "ArrowDown") : ("ArrowLeft", "ArrowRight")
  let target = switch Dom.Event.key(event) {
  | key if key == previous && count > 0 => Some(mod(index - 1 + count, count))
  | key if key == next && count > 0 => Some(mod(index + 1, count))
  | "Home" if count > 0 => Some(0)
  | "End" if count > 0 => Some(count - 1)
  | _ => None
  }
  target->Option.map(target => {
    Dom.Event.preventDefault(event)
    let element = all->Array.getUnsafe(target)
    Dom.focus(element)
    element
  })
}
