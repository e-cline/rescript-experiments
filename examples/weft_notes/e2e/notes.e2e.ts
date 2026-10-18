// What only a browser can show: real HTML streaming, real chunk loading, focus, and the history.
// Everything that can be checked without one is, in `tests/` (through the plugin's harness).

import {expect, test, type APIRequestContext} from '@playwright/test';

const release = (request: APIRequestContext, gate: string) =>
  request.post(`/test/gates/release/${encodeURIComponent(gate)}`);

const openGates = async (request: APIRequestContext, ...notes: string[]) => {
  for (const note of notes) {
    for (const part of ['body', 'comments', 'related']) {
      await release(request, `${part}:${note}`);
    }
  }
};

test.beforeEach(async ({request}) => {
  // Every gate closed, and the notes as they started.
  await request.post('/test/gates/manual');
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
  await page.locator('#note-link-1').click();
  await expect(page.locator('#like')).toHaveText('3 likes');
  expect(likeChunks).toHaveLength(1);
  await page.locator('#related-2').click();
  await expect(page.locator('#title')).toHaveText('Ideas');
  await expect(page.locator('#like')).toHaveText('5 likes');
  expect(likeChunks).toHaveLength(1);
});

test("saving a title refetches the header's frame, keeping the input's focus and selection", async ({
  page,
  request,
}) => {
  await openGates(request, '1');
  await page.goto('/notes/1');
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
