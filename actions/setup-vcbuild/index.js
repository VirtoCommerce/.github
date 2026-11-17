const core = require('@actions/core');
const exec = require('@actions/exec');
const fs = require('fs');
const os = require('os');
const path = require('path');

// The vc-build version this release of the action installs. Bump it here, check it
// with the "vc-build canary" workflow, and release a new tag of this repository:
// the module repos get a new vc-build only through that tag.
const VCBUILD_VERSION = '3.1002.0-alpha.301';

// vc-build runs on .NET 10 and registers MSBuild from SDK 10 in its process.
// The dotnet it starts (restore, build, test) must pick an SDK 10 too: on SDK 11
// the restore fails. Pin SDK 10 with a global.json one level above the
// workspace, so the repository tree stays clean and a repository's own
// global.json, being closer, still wins.
function pinSdk10()
{
    const workspace = process.env.GITHUB_WORKSPACE;
    if (!workspace) {
        core.warning('GITHUB_WORKSPACE is not set, SDK 10 is not pinned');
        return;
    }

    const globalJson = path.join(path.dirname(workspace), 'global.json');
    if (fs.existsSync(globalJson)) {
        core.info(`${globalJson} already exists, leaving it as is`);
        return;
    }

    const content = { sdk: { version: '10.0.100', rollForward: 'latestFeature' } };
    fs.writeFileSync(globalJson, JSON.stringify(content, null, 2) + '\n');
    core.info(`Pinned SDK 10 in ${globalJson}`);
}

async function run()
{
    const cwd = process.env.RUNNER_TEMP || os.homedir();

    // vc-build ships with rollForward=LatestMajor, so on a runner that has a newer
    // .NET (11+) it runs on that runtime and NUKE fails in NukeBuild's type
    // initializer. Major keeps it on the .NET 10 runtime it targets, and still
    // rolls an app forward when its own major version is not installed.
    // The environment variable overrides the tool's runtimeconfig.json.
    
    // core.exportVariable('DOTNET_ROLL_FORWARD', 'Major');
    // process.env.DOTNET_ROLL_FORWARD = 'Major';

    // pinSdk10();

    const version = core.getInput('version').trim() || VCBUILD_VERSION;
    core.info(`vc-build version: ${version}`);
    // Written to GITHUB_OUTPUT directly: the @actions/core committed in node_modules
    // predates file commands, and its setOutput prints the deprecated set-output command.
    if (process.env.GITHUB_OUTPUT) {
        fs.appendFileSync(process.env.GITHUB_OUTPUT, `version=${version}${os.EOL}`);
    }

    await exec.exec("dotnet --list-sdks");
    // update installs the tool when it is missing, and with --allow-downgrade
    // also switches an already installed vc-build to this exact version.
    await exec.exec('dotnet',
        ['tool', 'update', '--global', 'VirtoCommerce.GlobalTool', '--version', version, '--allow-downgrade',
         '--add-source', 'https://api.nuget.org/v3/index.json', '--ignore-failed-sources'],
        { cwd });
    core.addPath(path.join(os.homedir(), '.dotnet', 'tools'));
}

run().catch(err => core.setFailed(err.message));
