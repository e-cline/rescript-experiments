/***
What the HTML renderer's and hydration's tests share: reading a stream, putting HTML in the page as
the parser would (and running its scripts), comparing DOMs, and a seeded PRNG.
*/

type reader
type readResult = {done: bool, value?: Uint8Array.t}
@send external getReader: Html.stream => reader = "getReader"
@send external read: reader => promise<readResult> = "read"
type decoder
@new external makeDecoder: unit => decoder = "TextDecoder"
@send external decode: (decoder, Uint8Array.t) => string = "decode"

/** Everything `stream` sends, as text, in the chunks it was sent in. */
let chunks = async stream => {
  let reader = stream->getReader
  let decoder = makeDecoder()
  let all = []
  let finished = ref(false)
  while !finished.contents {
    switch await reader->read {
    | {done: false, value} => all->Array.push(decoder->decode(value))
    | _ => finished := true
    }
  }
  all
}

/** Puts `markup` in a fresh container, runs the runtime, and returns the container. */
let page: string => Dom.element = %raw(`markup => {
  const container = document.createElement("div");
  document.body.appendChild(container);
  container.innerHTML = markup;
  return container;
}`)

/** Appends a segment's markup (without its script) to the document, as the parser would. */
let arrive: string => unit = %raw(`markup => {
  const holder = document.createElement("div");
  holder.innerHTML = markup.replace(/<script>[^<]*<\/script>/g, "");
  for (const node of [...holder.childNodes]) document.body.appendChild(node);
}`)

/** Runs a segment's script (or the runtime), as the browser would when it reaches it. */
let run: string => unit = %raw(`markup => {
  for (const [, code] of markup.matchAll(/<script>([^<]*)<\/script>/g)) (0, eval)(code);
}`)

/** The container's nodes, as markup (the comment markers included). */
let markup: Dom.element => string = %raw(`container => container.innerHTML`)

/**
A container's DOM as a string to compare: elements with their attributes sorted (`value`, `checked`
and `selected` left out, and their properties added instead, since a client render sets those as
properties), text nodes, and nothing else (no comments, no `<template>`s, as hydration skips them).
*/
let structure: Dom.element => string = %raw(`container => {
  const walk = (node) => {
    // An empty text node can't be in HTML; hydration makes it.
    if (node.nodeType === 3) return node.data === "" ? "" : "T(" + node.data + ")";
    if (node.nodeType !== 1 || node.localName === "template") return "";
    // A textarea's text is its value (compared below), which a client render sets as a property.
    const children = node.localName === "textarea" ? [] : [...node.childNodes];
    const attributes = [...node.attributes]
      .filter((a) => !["value", "checked", "selected"].includes(a.name))
      // A style compared as the browser parsed it, however it was written.
      .map((a) => a.name + "=" + (a.name === "style" ? node.style.cssText : a.value))
      .sort();
    const properties = [];
    if ("value" in node && ["input", "textarea", "select"].includes(node.localName))
      properties.push("value:" + node.value);
    if (node.localName === "input") properties.push("checked:" + node.checked);
    return node.localName + "[" + attributes.concat(properties).join(",") + "](" +
      children.map(walk).join("") + ")";
  };
  return [...container.childNodes].map(walk).join("");
}`)

let clientRender = element => {
  let container = Dom.createElement(Dom.document, "div")
  let root = Client.createRoot(container)
  Client.act(() => Client.render(root, element))
  container
}

/** A seeded Lehmer PRNG, so failures reproduce. */
module Random = {
  type t = ref<float>
  let make = (seed: float): t => ref(seed)
  let next = (state: t): float => {
    let product = state.contents *. 48271.0
    state := product -. 2147483647.0 *. Math.floor(product /. 2147483647.0)
    state.contents
  }
  let intBelow = (state: t, bound: int): int => mod(Float.toInt(next(state)), bound)
  let pick = (state: t, items: array<'a>): 'a =>
    items->Array.getUnsafe(intBelow(state, Array.length(items)))
}
