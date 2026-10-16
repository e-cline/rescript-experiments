import {renderToStaticMarkup} from 'react-dom/server';
import {describe, expect, test} from 'vite-plus/test';

import {Greeting} from '../src/index';

describe('Greeting (ReScript + @rescript/react, consumed from TSX)', () => {
  test('renders the expected text and applies the CSS Module class', () => {
    const html = renderToStaticMarkup(<Greeting name="world" />);
    expect(html).toContain('Hello, world!');
    expect(html).toContain('base64: d29ybGQ='); // btoa("world")
    expect(html).toMatch(/class="[^"]*greeting[^"]*"/);
  });
});
