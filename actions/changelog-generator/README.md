# changelog-generator

Generates changelog

## outputs:

### changelog:

    description: 'Result'

## Example of usage

```yaml
- name: Get changelog
  id: changelog
  uses: VirtoCommerce/.github/actions/changelog-generator@v3.1000.1
```

## Commit formats

Commits since the latest release are read with `git log` and grouped by [Conventional Commits](https://www.conventionalcommits.org) type:

| Type | Section |
|------|---------|
| `feat` | 🎯 Development |
| `perf`, `refactor`, `test` | 📈 Improvements |
| `fix` | 🐞 Bug fixes |
| `style`, `chore`, `build` | 🗿 Chore |
| `docs` | 📝 Documentation |
| `ci` | not printed |

- **Conventional subject** — `type: text`, `type(scope): text`, `type!: text`, `type(scope)!: text`. The scope is dropped; `!` or a `BREAKING CHANGE:` footer prefixes the line with `BREAKING: `.
- **Jira-key subject** — `ABC-123: text`. Every `type: ` marker in the body (same forms as above) becomes a line in its type's section; `Co-authored-by:` and `Signed-off-by:` trailers are ignored. A body without markers, or one starting with a Jira key, puts the subject (without the key) under 🎯 Development.
- **Skipped** — anything else: merge commits, `revert:` / `Revert "…"`, free-text subjects, unknown or capitalized types.

## Development

```bash
npm ci
npm test        # node:test unit tests in src/
npm run build   # rebuild dist/ with @vercel/ncc; commit the result
```
