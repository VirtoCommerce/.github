# vc-argocd-cli

ArgoCD command line action

## inputs:

### server:

    description: 'ArgoCD server'
    required: true

### username:

    description: 'ArgoCD username'
    required: true

### password:

    description: 'ArgoCD password'
    required: true

### command:

    description: 'Run ArgoCD command'
    required: false

## Example of usage

```yaml
- name: ArgoCD CLI
  uses: VirtoCommerce/.github/actions/vc-argocd-cli@v3.1000.1
  with:
    server: ${{ secrets.ARGOCD_SERVER }}
    username: ${{ secrets.ARGOCD_USERNAME }}
    password: ${{ secrets.ARGOCD_PASSWORD }}
    command: 'app sync my-app'
```
