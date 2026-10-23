// What only a browser can show: real HTML streaming and parsing, real chunk loading, focus, and the
// history. Everything that can be checked without one is, in `tests/` (through the plugin's harness).

import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from '@playwright/test';

const release = (request: APIRequestContext, gate: string) =>
  request.post(`/test/gates/release/${encodeURIComponent(gate)}`);

const openGates = async (request: APIRequestContext, ...notes: string[]) => {
  for (const note of notes) {
    for (const part of ['body', 'comments', 'related']) {
      await release(request, `${part}:${note}`);
    }
  }
};

/**
 * Waits until the bootstrap has hydrated the element `selector` matches (it has its props): a
 * click before then does nothing.
 */
const hydrated = (page: Page, selector: string) =>
  page.waitForFunction((selector) => {
    const element = document.querySelector(selector);
    return element !== null && '$$resFiberProps' in element;
  }, selector);

/** What the console says that it shouldn't: errors and warnings. */
let complaints: string[] = [];

test.beforeEach(async ({page, request}) => {
  // Every gate closed, and the notes as they started.
  await request.post('/test/gates/manual');
  complaints = [];
  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'warning') {
      complaints.push(message.text());
    }
  });
  page.on('pageerror', (error) => complaints.push(String(error)));
});

test.afterEach(() => {
  expect(complaints).toEqual([]);
});

test('the first page streams: the shell and the first row, then each boundary as its gate opens', async ({
  page,
  request,
}) => {
  // Not waiting for `load`: the page is still streaming, so it hasn't loaded.
  await page.goto('/notes/1', {waitUntil: 'commit'});
  await expect(page.locator('#title')).toHaveText('Groceries');
  await expect(page.locator('#body-loading')).toBeVisible();
  await expect(page.locator('#related-loading')).toBeVisible();
  await release(request, 'related:1');
  await expect(page.locator('#related')).toBeVisible();
  await expect(page.locator('#body-loading')).toBeVisible();
  await release(request, 'body:1');
  await expect(page.locator('#note-body')).toHaveText('Milk, eggs, bread.');
  await expect(page.locator('#comment-list-loading')).toBeVisible();
  await release(request, 'comments:1');
  await expect(page.locator('#comment-list')).toContainText(
    "Ada: Don't forget coffee.",
  );
});

test("an entrypoint's chunk is requested once a page uses it, and only once", async ({
  page,
  request,
}) => {
  await openGates(request, '1', '2');
  const likeChunks: string[] = [];
  page.on('request', (sent) => {
    if (/\/assets\/LikeButton[^/]*\.js$/.test(new URL(sent.url()).pathname)) {
      likeChunks.push(sent.url());
    }
  });
  await page.goto('/');
  await expect(page.locator('#notes')).toBeVisible();
  expect(likeChunks).toEqual([]);
  await hydrated(page, '#note-link-1');
  await page.locator('#note-link-1').click();
  await expect(page.locator('#like')).toHaveText('3 likes');
  expect(likeChunks).toHaveLength(1);
  await page.locator('#related-2').click();
  await expect(page.locator('#title')).toHaveText('Ideas');
  await expect(page.locator('#like')).toHaveText('5 likes');
  expect(likeChunks).toHaveLength(1);
});

test("saving a title refetches the saved title, keeping the input's focus and selection", async ({
  page,
  request,
}) => {
  await openGates(request, '1');
  await page.goto('/notes/1');
  await hydrated(page, '#title-input');
  const input = page.locator('#title-input');
  await input.fill('Groceries!');
  await input.evaluate((element: HTMLInputElement) => {
    (element as HTMLInputElement & {marked?: boolean}).marked = true;
    element.setSelectionRange(2, 5);
  });
  // Enter submits the form without moving the focus off the input.
  await input.press('Enter');
  await expect(page.locator('#saved-at')).toHaveText('Saved: revision 1');
  await expect(page.locator('#title')).toHaveText('Groceries!');
  expect(
    await input.evaluate((element: HTMLInputElement) => ({
      same: (element as HTMLInputElement & {marked?: boolean}).marked === true,
      focused: document.activeElement === element,
      selection: [element.selectionStart, element.selectionEnd],
      value: element.value,
    })),
  ).toEqual({
    same: true,
    focused: true,
    selection: [2, 5],
    value: 'Groceries!',
  });
});

test("navigating between notes keeps the like button's state, and the back button works", async ({
  page,
  request,
}) => {
  await openGates(request, '1', '2');
  await page.goto('/notes/1');
  await hydrated(page, '#like');
  await page.locator('#like').click();
  await expect(page.locator('#like')).toHaveText('3 likes (you liked this)');
  await page.locator('#related-2').click();
  await expect(page.locator('#title')).toHaveText('Ideas');
  await expect(page).toHaveURL(/\/notes\/2$/);
  await expect(page.locator('#like')).toHaveText('5 likes (you liked this)');
  await page.goBack();
  await expect(page).toHaveURL(/\/notes\/1$/);
  await expect(page.locator('#title')).toHaveText('Groceries');
  // The like went to the server, and the button still knows it was liked here.
  await expect(page.locator('#like')).toHaveText('4 likes (you liked this)');
});

test('posting a comment goes through its RPC, as JSON with its header, and a refresh shows it', async ({
  page,
  request,
}) => {
  await openGates(request, '1');
  await page.goto('/notes/1');
  await hydrated(page, '#comment-text');
  await page.locator('#comment-author').fill('Me');
  await page.locator('#comment-text').fill('  From a browser  ');
  const posted = page.waitForRequest(
    (sent) => new URL(sent.url()).pathname === '/_weft/rpc/notes.addComment',
  );
  await page.locator('#post-comment').click();
  const sent = await posted;
  expect(sent.method()).toBe('POST');
  expect(sent.headers()['content-type']).toBe('application/json');
  expect(sent.headers()['x-weft-rpc']).toBe('1');
  // `prepare` trimmed it, on the client.
  expect(sent.postDataJSON()).toEqual({
    noteId: '1',
    author: 'Me',
    text: 'From a browser',
  });
  expect((await sent.response())?.status()).toBe(200);
  // The refresh's comments wait on their gate again.
  await release(request, 'comments:1');
  await expect(page.locator('#comment-list')).toContainText(
    'Me: From a browser',
  );
  await expect(page.locator('#comment-text')).toHaveValue('');
});

test("a boundary's content is painted before the bootstrap has loaded, and hydrated once it has", async ({
  page,
  request,
}) => {
  // The bootstrap's chunk (the client build's entry) held back.
  let releaseBootstrap!: () => void;
  const held = new Promise<void>((resolve) => {
    releaseBootstrap = resolve;
  });
  await page.route(/\/assets\/client-[^/]*\.js$/, async (route) => {
    await held;
    await route.continue();
  });
  await page.goto('/notes/1', {waitUntil: 'commit'});
  await expect(page.locator('#title')).toHaveText('Groceries');
  await expect(page.locator('#body-loading')).toBeVisible();
  await release(request, 'body:1');
  // Swapped in by the page's own inline script.
  await expect(page.locator('#note-body')).toHaveText('Milk, eggs, bread.');
  expect(
    await page.evaluate(
      () => '$$resFiberProps' in document.querySelector('#title')!,
    ),
  ).toBe(false);
  releaseBootstrap();
  await hydrated(page, '#note-body');
  await hydrated(page, '#like');
  await page.locator('#like').click();
  await expect(page.locator('#like')).toHaveText('3 likes (you liked this)');
});

test.describe('with JavaScript off', () => {
  test.use({javaScriptEnabled: false});

  test('the page is readable: the shell, as the server rendered it', async ({
    page,
    request,
  }) => {
    await openGates(request, '1');
    await page.goto('/notes/1');
    await expect(page.locator('#title')).toHaveText('Groceries');
    await expect(page.locator('#saved-at')).toHaveText('Saved: never');
    await expect(page.locator('#title-input')).toHaveValue('Groceries');
    await expect(page.locator('#comments-section h2')).toHaveText('Comments');
    await expect(page.locator('#home-link')).toHaveAttribute('href', '/');
  });
});
