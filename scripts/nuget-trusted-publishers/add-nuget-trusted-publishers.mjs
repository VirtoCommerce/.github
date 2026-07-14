/**
 * Create NuGet.org Trusted Publishing policies for module repositories.
 *
 * WHY THIS ASKS FOR A COOKIE (and not a username/password):
 *   NuGet.org has NO public API for managing Trusted Publishing policies. They can
 *   only be created through the website, via the anti-forgery-protected MVC endpoint
 *   POST /account/GenerateTrustedPublisherPolicy (see NuGetGallery UsersController),
 *   which requires an authenticated *session cookie*. NuGet.org login is federated
 *   Microsoft-account auth (MFA + corporate SSO), so there is no password/API-key you
 *   can hand a script. The one credential the site accepts is the session cookie your
 *   browser already holds after you log in.
 *
 * HOW IT WORKS (no browser, nothing stored):
 *   1. You log in to nuget.org in your NORMAL browser (where your SSO plugin works).
 *   2. You paste that session's Cookie header when this script prompts for it.
 *   3. The script GETs /account/trustedpublishing to grab a matching anti-forgery
 *      token, then POSTs the 3 policies for each repo. The cookie lives only in
 *      memory for the run and is never written to disk.
 *
 * Each module repo gets 3 policies (Environment left blank), one per workflow:
 *   module-ci.yml, publish-nugets.yml, module-release-hotfix.yml
 *
 * GETTING THE COOKIE (once per run):
 *   - Log in at https://www.nuget.org and open your account -> Trusted Publishing.
 *   - Open DevTools (F12) -> Network tab -> click any www.nuget.org request.
 *   - Under Request Headers, copy the whole value of the `cookie:` header.
 *     (Or right-click the request -> Copy -> Copy as cURL, save to a file, and pass
 *      it with --curl <file>; the script extracts the cookie from it.)
 *
 * USAGE:
 *   node add-nuget-trusted-publishers.mjs --repos vc-module-cart
 *   node add-nuget-trusted-publishers.mjs --repos vc-module-cart,vc-module-news
 *   node add-nuget-trusted-publishers.mjs --repos vc-module-cart --dry-run
 *   node add-nuget-trusted-publishers.mjs --repos vc-module-cart --curl ./req.txt
 *
 * OPTIONS:
 *   --repos a,b,c     Explicit repo names (with or without the owner/ prefix). Required.
 *   --owner <name>    NuGet.org package owner that will own the policies.  Default: VirtoCommerce
 *   --github-owner    GitHub org used as the policy's RepositoryOwner.      Default: VirtoCommerce
 *   --workflows a,b   Override the workflow file list (comma-separated).
 *   --curl <file>     Read the cookie from a saved "Copy as cURL" file instead of prompting.
 *   --dry-run         Show what would be created; do not POST.
 *   --help            Show this help.
 *
 * Requires Node 18+ (uses built-in fetch). No npm install needed.
 */

import readline from 'node:readline';
import { readFileSync } from 'node:fs';

const NUGET_ORIGIN = 'https://www.nuget.org';
const TP_URL = `${NUGET_ORIGIN}/account/trustedpublishing`;
const GITHUB_ACTIONS_PUBLISHER = 'GitHubActions';
const DEFAULT_WORKFLOWS = ['module-ci.yml', 'publish-nugets.yml', 'module-release-hotfix.yml'];
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

// ---------------------------------------------------------------------------
// Args
// ---------------------------------------------------------------------------
function parseArgs(argv) {
  const args = {
    repos: [],
    owner: 'VirtoCommerce',
    githubOwner: 'VirtoCommerce',
    workflows: DEFAULT_WORKFLOWS,
    curl: '',
    dryRun: false,
    help: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    switch (a) {
      case '--repos': args.repos = splitList(next()); break;
      case '--owner': args.owner = next(); break;
      case '--github-owner': args.githubOwner = next(); break;
      case '--workflows': args.workflows = splitList(next()); break;
      case '--curl': args.curl = next(); break;
      case '--dry-run': args.dryRun = true; break;
      case '--help': case '-h': args.help = true; break;
      default: throw new Error(`Unknown argument: ${a}`);
    }
  }
  return args;
}

const splitList = (s) => String(s || '').split(',').map((x) => x.trim()).filter(Boolean);

// Repo names may arrive as "owner/name"; the policy criteria wants the bare name.
const bareRepo = (r) => (r.includes('/') ? r.split('/').pop() : r);

// ---------------------------------------------------------------------------
// Credentials (session cookie) — prompted per run, kept in memory only
// ---------------------------------------------------------------------------
async function readCookie(curlFile) {
  let raw;
  if (curlFile) {
    raw = readFileSync(curlFile, 'utf8');
  } else if (!process.stdin.isTTY) {
    raw = await readAllStdin();
  } else {
    raw = await prompt(
      'Log in to nuget.org in your browser, then paste your Cookie header here.\n' +
        '(DevTools -> Network -> a www.nuget.org request -> Request Headers -> "cookie:" value)\n' +
        'Cookie: ',
    );
  }
  const cookie = extractCookie(raw);
  if (!cookie || !cookie.includes('=')) {
    throw new Error('No cookie found in the input. Paste the full "cookie:" header value.');
  }
  return cookie;
}

function extractCookie(input) {
  const text = String(input || '').trim();
  // "Copy as cURL" forms: -H 'cookie: ...'  or  -b '...' / --cookie '...'
  let m = text.match(/-H\s+\$?['"]cookie:\s*([\s\S]*?)['"]/i);
  if (m) return m[1].trim();
  m = text.match(/(?:-b|--cookie)\s+\$?['"]([\s\S]*?)['"]/i);
  if (m) return m[1].trim();
  // Raw header, optionally prefixed with "cookie:".
  m = text.match(/^\s*cookie:\s*([\s\S]+)$/i);
  if (m) return m[1].trim();
  return text;
}

function readAllStdin() {
  return new Promise((resolve) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => (data += c));
    process.stdin.on('end', () => resolve(data));
  });
}

function prompt(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

// ---------------------------------------------------------------------------
// Cookie jar helpers (we manage the Cookie header ourselves)
// ---------------------------------------------------------------------------
function parseCookieHeader(header) {
  const jar = new Map();
  for (const part of String(header).split(';')) {
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    const name = part.slice(0, eq).trim();
    if (name) jar.set(name, part.slice(eq + 1).trim());
  }
  return jar;
}

function applySetCookies(jar, setCookies) {
  for (const sc of setCookies || []) {
    const first = sc.split(';')[0];
    const eq = first.indexOf('=');
    if (eq < 0) continue;
    const name = first.slice(0, eq).trim();
    const value = first.slice(eq + 1).trim();
    // A deleted cookie (expired/empty) is removed rather than sent back.
    if (name) {
      if (value === '' || /expires=Thu, 01 Jan 1970/i.test(sc)) jar.delete(name);
      else jar.set(name, value);
    }
  }
}

const serializeJar = (jar) => [...jar.entries()].map(([k, v]) => `${k}=${v}`).join('; ');

// ---------------------------------------------------------------------------
// NuGet page state: anti-forgery token, endpoint URL, owners, existing policies
// ---------------------------------------------------------------------------
async function fetchTpState(jar) {
  const res = await fetch(TP_URL, {
    headers: { Cookie: serializeJar(jar), 'User-Agent': USER_AGENT, Accept: 'text/html' },
    redirect: 'follow',
  });
  applySetCookies(jar, res.headers.getSetCookie?.());
  const body = await res.text();
  const authed = !/logon/i.test(res.url) && /__RequestVerificationToken/.test(body);
  if (!authed) return { authed: false };

  const token = extractToken(body);
  if (!token) return { authed: false };

  const initial = extractInitialData(body);
  const generateUrl = initial?.GenerateUrl
    ? new URL(initial.GenerateUrl, NUGET_ORIGIN).toString()
    : `${NUGET_ORIGIN}/account/GenerateTrustedPublisherPolicy`;
  const owners = (initial?.PackageOwners || []).map((o) => (typeof o === 'string' ? o : o.Owner || o.Username || o.name));
  const policies = initial?.Policies || [];
  return { authed: true, token, generateUrl, owners, policies };
}

function extractToken(html) {
  const patterns = [
    /name="__RequestVerificationToken"[^>]*\bvalue="([^"]+)"/i,
    /\bvalue="([^"]+)"[^>]*name="__RequestVerificationToken"/i,
  ];
  for (const re of patterns) {
    const m = html.match(re);
    if (m) return decodeEntities(m[1]);
  }
  return null;
}

// The view emits `var initialData = @Html.ToJson(new { ... });` inline. Pull the
// object out with a brace-depth scan that respects quoted strings.
function extractInitialData(html) {
  const at = html.indexOf('initialData');
  if (at < 0) return null;
  const braceStart = html.indexOf('{', at);
  if (braceStart < 0) return null;

  let depth = 0;
  let inStr = false;
  let quote = '';
  let esc = false;
  for (let i = braceStart; i < html.length; i++) {
    const ch = html[i];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === '\\') esc = true;
      else if (ch === quote) inStr = false;
      continue;
    }
    if (ch === '"' || ch === "'") { inStr = true; quote = ch; continue; }
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) {
        const raw = html.slice(braceStart, i + 1);
        try { return JSON.parse(raw); }
        catch { try { return JSON.parse(decodeEntities(raw)); } catch { return null; } }
      }
    }
  }
  return null;
}

const decodeEntities = (s) =>
  String(s)
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');

function policyExists(policies, { owner, githubOwner, repo, workflow }) {
  return policies.some((p) => {
    const d = p.PolicyDetails || p;
    return (
      String(p.Owner || '').toLowerCase() === owner.toLowerCase() &&
      String(d.RepositoryOwner || '').toLowerCase() === githubOwner.toLowerCase() &&
      String(d.Repository || '').toLowerCase() === repo.toLowerCase() &&
      String(d.WorkflowFile || '').toLowerCase() === workflow.toLowerCase() &&
      !String(d.Environment || '')
    );
  });
}

async function createPolicy(jar, { generateUrl, token, policyName, owner, criteria }) {
  const res = await fetch(generateUrl, {
    method: 'POST',
    headers: {
      Cookie: serializeJar(jar),
      'User-Agent': USER_AGENT,
      'Content-Type': 'application/x-www-form-urlencoded',
      'X-Requested-With': 'XMLHttpRequest',
      Referer: TP_URL,
    },
    body: new URLSearchParams({
      policyName,
      owner,
      criteria: JSON.stringify(criteria),
      __RequestVerificationToken: token,
    }),
    redirect: 'manual',
  });
  applySetCookies(jar, res.headers.getSetCookie?.());
  const status = res.status;
  const text = await res.text();
  if (status >= 200 && status < 300) {
    // The endpoint returns 200 with a JSON error string for validation failures too.
    if (/"?(error|Message)"?\s*:/i.test(text) && !/policyName|PolicyDetails|Key/i.test(text)) {
      return { ok: false, reason: snippet(text) };
    }
    return { ok: true };
  }
  return { ok: false, reason: `HTTP ${status}: ${snippet(text)}` };
}

const snippet = (t) => String(t).replace(/\s+/g, ' ').trim().slice(0, 300);

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { printHelp(); return 0; }

  const repos = [...new Set(args.repos.map(bareRepo))].sort();
  if (repos.length === 0) {
    throw new Error('No repos specified. Use --repos <a,b,c>.');
  }

  console.log(`Owner (nuget):   ${args.owner}`);
  console.log(`RepositoryOwner: ${args.githubOwner}`);
  console.log(`Workflows:       ${args.workflows.join(', ')}`);
  console.log(`Repos (${repos.length}):       ${repos.join(', ')}`);
  if (args.dryRun) console.log('Mode:            DRY RUN (no changes will be made)');
  console.log('');

  const jar = parseCookieHeader(await readCookie(args.curl));
  const state = await fetchTpState(jar);
  if (!state.authed) {
    throw new Error(
      'The cookie did not authenticate (expired or incomplete). Log in to nuget.org again ' +
        'and paste a fresh "cookie:" header.',
    );
  }

  if (state.owners.length && !state.owners.some((o) => o.toLowerCase() === args.owner.toLowerCase())) {
    console.warn(
      `WARNING: "${args.owner}" is not in your available package owners [${state.owners.join(', ')}]. ` +
        'The POST will likely be rejected. Pass --owner with a valid owner.',
    );
  }

  const results = [];
  for (const repo of repos) {
    for (const workflow of args.workflows) {
      const policyName = `${repo}-${workflow.replace(/\.ya?ml$/i, '')}`;
      const criteria = {
        Name: GITHUB_ACTIONS_PUBLISHER,
        RepositoryOwner: args.githubOwner,
        Repository: repo,
        WorkflowFile: workflow,
        Environment: '',
      };
      const label = `${repo} / ${workflow}`;

      if (policyExists(state.policies, { owner: args.owner, githubOwner: args.githubOwner, repo, workflow })) {
        results.push({ label, status: 'SKIP' });
        log('SKIP', label, 'already exists');
        continue;
      }
      if (args.dryRun) {
        results.push({ label, status: 'DRYRUN' });
        log('DRYRUN', label, `would create "${policyName}"`);
        continue;
      }

      const r = await createPolicy(jar, {
        generateUrl: state.generateUrl,
        token: state.token,
        policyName,
        owner: args.owner,
        criteria,
      });
      if (r.ok) {
        results.push({ label, status: 'OK' });
        log('OK', label, `created "${policyName}"`);
      } else {
        results.push({ label, status: 'ERROR' });
        log('ERROR', label, r.reason);
      }
    }
  }

  console.log('\nSummary:');
  const byStatus = results.reduce((m, r) => ((m[r.status] = (m[r.status] || 0) + 1), m), {});
  for (const [k, v] of Object.entries(byStatus)) console.log(`  ${k.padEnd(7)} ${v}`);

  return results.some((r) => r.status === 'ERROR') ? 1 : 0;
}

function log(status, label, reason) {
  const colors = { OK: 32, SKIP: 90, DRYRUN: 36, ERROR: 31 };
  const c = colors[status] || 37;
  console.log(`\x1b[${c}m[${status.padEnd(6)}]\x1b[0m ${label}: ${reason}`);
}

function printHelp() {
  console.log(`See the header comment in ${import.meta.url}\n`);
  console.log('Common usage:');
  console.log('  node add-nuget-trusted-publishers.mjs --repos vc-module-cart');
  console.log('  node add-nuget-trusted-publishers.mjs --repos vc-module-cart,vc-module-news');
  console.log('  node add-nuget-trusted-publishers.mjs --repos vc-module-cart --dry-run');
  console.log('  node add-nuget-trusted-publishers.mjs --repos vc-module-cart --curl ./req.txt');
}

main()
  .then((code) => process.exit(code))
  .catch((err) => {
    console.error(`\nFATAL: ${err.message}`);
    process.exit(1);
  });
