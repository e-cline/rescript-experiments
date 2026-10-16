# Changesets

This directory holds [changesets](https://github.com/changesets/changesets): one small Markdown file
per change, naming the packages it affects and whether each gets a patch, minor or major bump.

Add one to any pull request that changes a published package:

```bash
pnpm changeset
```

See [CONTRIBUTING.md](../CONTRIBUTING.md#releasing) for how they turn into releases.
