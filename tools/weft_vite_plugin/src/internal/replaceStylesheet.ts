// What the client does on `weft:css` (`virtual:weft/client` has this function's source).

/**
 * Swaps the page's link to the stylesheet `href` (its URL without a query) for a fresh one, and
 * takes the old away once the new has loaded, so the page is never without it. What's waiting for
 * the sheet has it already: it had loaded.
 */
export function replaceStylesheet(href: string): void {
  for (const link of document.querySelectorAll('link[rel="stylesheet"]')) {
    const current = link.getAttribute('href');
    if (current === null || current.split('?')[0] !== href) continue;
    const fresh = link.cloneNode() as Element;
    fresh.setAttribute('href', `${href}?t=${Date.now()}`);
    const done = () => link.remove();
    fresh.addEventListener('load', done, {once: true});
    fresh.addEventListener('error', done, {once: true});
    link.after(fresh);
  }
}
