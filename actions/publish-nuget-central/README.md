# publish-nuget-central

Publish NuGet packages through `VirtoCommerce/vc-nuget-publisher`, the one repository with a
nuget.org Trusted Publishing policy. The action uploads the packages as an artifact, dispatches
the publisher's `publish.yml` with this run's id, and waits for it. A failed push fails the step.

The job needs no `id-token` permission and no nuget.org key: the publisher run gets the key.

## inputs:

### githubToken:

    description: 'Token that can dispatch and watch workflow runs in the publisher repository'
    required: true

### path:

    description: 'Folder with the .nupkg and .snupkg files to publish'
    required: false
    default: 'artifacts'

### publisherRepository:

    description: 'Repository whose workflow pushes to nuget.org'
    required: false
    default: 'VirtoCommerce/vc-nuget-publisher'

### publisherWorkflow:

    description: 'Workflow file in the publisher repository'
    required: false
    default: 'publish.yml'

## outputs:

### publishRunUrl:

    description: 'URL of the publisher run that pushed the packages'

## Example of usage

```yaml
- name: Pack Nuget
  run: vc-build Pack -skip Clean+Restore+Compile+Test

- name: Publish Nuget
  uses: VirtoCommerce/.github/actions/publish-nuget-central@v3.1000.7
  with:
    githubToken: ${{ secrets.REPO_TOKEN }}
```
