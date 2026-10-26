/***
For tests in jsdom, which has neither `<dialog>`'s `showModal` and `close` nor the Popover API:
`installJsdomShims()` adds enough of both for weft_ui's overlays to open, close and say so, as a
browser's do. Call it once, before rendering (at the top of a test file, or in the module a test
suite's pages share). It does nothing where the real ones are there.

What it does, and doesn't:

- A dialog's `show` and `showModal` set `open` and focus the first focusable element in it (or one
  with `autofocus`); `close` removes it and fires `close`. Escape, while a modal one is open, fires
  `cancel` on the newest, and closes it unless that's cancelled.
- An element with a `popover` attribute gets `showPopover`, `hidePopover` and `togglePopover`, firing
  `beforetoggle` and `toggle` (with `newState` and `oldState`). A button's `popovertarget` toggles its
  target when clicked. Escape, or a click outside, hides the newest `auto` popover.
- jsdom hides every popover (it never matches `:popover-open`), and won't focus in a hidden one, so
  a stylesheet the shim adds shows those it shows (they have `data-popover-open`, for tests too).
- `scrollIntoView` does nothing (jsdom has none).
- It doesn't make anything inert, trap focus, or lay anything out: those are the browser's, and
  weft_ui's browser tests check them.
*/

let installJsdomShims: unit => unit = %raw(`() => {
  const window = globalThis.window;
  if (!window || window.__weftUiShims) return;
  window.__weftUiShims = true;
  const {document, HTMLDialogElement, HTMLElement, Event} = window;

  const focusables = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';
  const focusFirst = (element) => {
    const target = element.querySelector('[autofocus]') ?? element.querySelector(focusables);
    target?.focus();
  };

  // jsdom lays nothing out, so there's nothing to scroll into view (a combobox's highlighted option).
  if (!window.Element.prototype.scrollIntoView) window.Element.prototype.scrollIntoView = () => {};

  // Dialogs
  const modals = [];
  if (HTMLDialogElement && !HTMLDialogElement.prototype.showModal) {
    const proto = HTMLDialogElement.prototype;
    if (!('open' in proto)) {
      Object.defineProperty(proto, 'open', {
        configurable: true,
        get() { return this.hasAttribute('open'); },
        set(value) { value ? this.setAttribute('open', '') : this.removeAttribute('open'); },
      });
    }
    proto.show = function () {
      if (this.hasAttribute('open')) return;
      this.setAttribute('open', '');
      focusFirst(this);
    };
    proto.showModal = function () {
      if (this.hasAttribute('open')) return;
      this.setAttribute('open', '');
      modals.push(this);
      focusFirst(this);
    };
    proto.close = function (returnValue) {
      if (!this.hasAttribute('open')) return;
      if (returnValue !== undefined) this.returnValue = returnValue;
      this.removeAttribute('open');
      const index = modals.indexOf(this);
      if (index >= 0) modals.splice(index, 1);
      this.dispatchEvent(new Event('close'));
    };
  }

  // Popovers. jsdom hides every element with a \`popover\` attribute (it never matches
  // \`:popover-open\`), and won't focus anything in a hidden one: those the shim shows, it shows.
  const style = document.createElement('style');
  style.textContent = '[popover][data-popover-open] { display: block !important; }';
  document.head.appendChild(style);
  const shown = new Set();
  const toggleEvent = (type, oldState, newState, cancelable) => {
    const event = new Event(type, {cancelable});
    Object.assign(event, {oldState, newState});
    return event;
  };
  if (!HTMLElement.prototype.showPopover) {
    const proto = HTMLElement.prototype;
    proto.showPopover = function () {
      if (shown.has(this)) return;
      if (!this.dispatchEvent(toggleEvent('beforetoggle', 'closed', 'open', true))) return;
      shown.add(this);
      this.setAttribute('data-popover-open', '');
      this.dispatchEvent(toggleEvent('toggle', 'closed', 'open', false));
    };
    proto.hidePopover = function () {
      if (!shown.has(this)) return;
      this.dispatchEvent(toggleEvent('beforetoggle', 'open', 'closed', false));
      shown.delete(this);
      this.removeAttribute('data-popover-open');
      this.dispatchEvent(toggleEvent('toggle', 'open', 'closed', false));
    };
    proto.togglePopover = function (force) {
      const open = force ?? !shown.has(this);
      open ? this.showPopover() : this.hidePopover();
      return open;
    };
  }
  const newestAuto = () =>
    [...shown].reverse().find((element) => element.getAttribute('popover') !== 'manual');

  document.addEventListener('click', (event) => {
    const invoker = event.target?.closest?.('[popovertarget]');
    if (invoker) {
      const target = document.getElementById(invoker.getAttribute('popovertarget'));
      const action = invoker.getAttribute('popovertargetaction') ?? 'toggle';
      if (target) {
        if (action === 'show') target.showPopover();
        else if (action === 'hide') target.hidePopover();
        else target.togglePopover();
      }
      return;
    }
    const open = newestAuto();
    if (open && !open.contains(event.target)) open.hidePopover();
  });

  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || event.defaultPrevented) return;
    const open = newestAuto();
    if (open) {
      open.hidePopover();
      return;
    }
    const modal = modals[modals.length - 1];
    if (modal && modal.dispatchEvent(new Event('cancel', {cancelable: true}))) modal.close();
  });
}`)
