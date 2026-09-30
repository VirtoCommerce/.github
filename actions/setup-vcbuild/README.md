# setup-vcbuild

Setups vc-build

## Example of usage

```yaml
- name: Setup vc-build
  uses: VirtoCommerce/.github/actions/setup-vcbuild@v3.1000.1
```

## Compile action

Use @vercel/ncc tool to compile your code and modules into one file used for distribution.

- Install vercel/ncc by running this command in your terminal.

```bash
npm i -g @vercel/ncc
```

- Compile your index.ts file.

```bash
ncc build ./src/index.ts --license licenses.txt
```
