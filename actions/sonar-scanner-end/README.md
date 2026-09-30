# sonar-scanner-end

Runs vc-build SonarQubeEnd

## Example of usage

```yaml
- name: SonarCloud End
  uses: VirtoCommerce/.github/actions/sonar-scanner-end@v3.1000.1
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
