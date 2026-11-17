const core = require('@actions/core');
const exec = require('@actions/exec');
const fs = require('fs');
const os = require('os');
const path = require('path');

// The vc-build version this release of the action installs. Bump it here, check it
// with the "vc-build canary" workflow, and release a new tag of this repository:
// the module repos get a new vc-build only through that tag.
const VCBUILD_VERSION = '3.1002.0';

async function run()
{
    const cwd = process.env.RUNNER_TEMP || os.homedir();

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
