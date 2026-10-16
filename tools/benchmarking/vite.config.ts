import {defineConfig} from 'vite-plus';

export default defineConfig({
  run: {
    tasks: {
      // `res-bench`'s tests (`cli/*.test.ts`), run by Node's own test runner,
      // which runs TypeScript directly as `res-bench` itself does. Not cached:
      // one of them runs a small benchmark program through `res-bench`'s
      // module hook, which no input file describes.
      test: {
        command: "node --test 'cli/*.test.ts'",
        cache: false,
      },
    },
  },
});
