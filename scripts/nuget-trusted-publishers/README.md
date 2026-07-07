# NuGet.org Trusted Publishing policies

Creates [Trusted Publishing](https://learn.microsoft.com/en-us/nuget/nuget-org/trusted-publishing)
policies on nuget.org for VirtoCommerce **module** repositories, so their GitHub
Actions workflows can push packages with short-lived OIDC keys instead of a
long-lived `NUGET_KEY`.

Each module repo gets **3 policies** (one per publishing workflow, Environment left blank):

| Workflow file               | Policy name pattern            |
| --------------------------- | ------------------------------ |
| `module-ci.yml`             | `<repo>-module-ci`             |
| `publish-nugets.yml`        | `<repo>-publish-nugets`        |
| `module-release-hotfix.yml` | `<repo>-module-release-hotfix` |

## Why it asks for a cookie

nuget.org has **no public API** for managing Trusted Publishing policies — they can
only be created on the website, via an anti-forgery-protected endpoint that requires
an authenticated **session cookie**. Login is federated Microsoft-account auth
(MFA + corporate SSO), so there's no password or API key a script can use, and
automating the login in a clean browser fails because the corporate SSO extension
isn't present. The workaround: you log in in your **normal** browser (where SSO
works) and hand the script the session cookie.

Nothing is stored — the cookie is read at runtime, kept in memory for the run only,
and never written to disk. There is no browser and no dependency to install
(pure Node 18+, built-in `fetch`).

## Get the cookie (once per run)

1. Log in at <https://www.nuget.org> and open your account → **Trusted Publishing**.
2. Open DevTools (F12) → **Network** tab → click any `www.nuget.org` request.
3. Under **Request Headers**, copy the whole value of the `cookie:` header.

> Alternatively, right-click the request → **Copy → Copy as cURL**, save it to a
> file, and pass `--curl <file>` — the script extracts the cookie from it.

## Usage

```bash
cd .github/scripts/nuget-trusted-publishers

# After creating a new module repo (you'll be prompted to paste the cookie):
node add-nuget-trusted-publishers.mjs --repos vc-module-cart

# Several at once:
node add-nuget-trusted-publishers.mjs --repos vc-module-cart,vc-module-news

# Preview only, no changes:
node add-nuget-trusted-publishers.mjs --repos vc-module-cart --dry-run

# Read the cookie from a saved "Copy as cURL" file instead of pasting:
node add-nuget-trusted-publishers.mjs --repos vc-module-cart --curl ./req.txt
```

The script is **idempotent**: existing identical policies are detected and skipped,
so re-running is safe. If the cookie has expired it will tell you to grab a fresh one.

### Options

| Option            | Default        | Description                                          |
| ----------------- | -------------- | ---------------------------------------------------- |
| `--repos a,b,c`   | *(required)*   | Repo names (with or without `owner/` prefix).        |
| `--owner`         | `VirtoCommerce`| nuget.org package owner that will own the policies.  |
| `--github-owner`  | `VirtoCommerce`| GitHub org used as the policy's `RepositoryOwner`.   |
| `--workflows a,b` | the 3 above    | Override the workflow file list.                     |
| `--curl <file>`   | *(prompt)*     | Read the cookie from a saved "Copy as cURL" file.    |
| `--dry-run`       | off            | Show what would be created; do not POST.             |

## New-repo checklist

After creating a `vc-module-*` repo, run:

```bash
node add-nuget-trusted-publishers.mjs --repos <new-repo-name>
```
