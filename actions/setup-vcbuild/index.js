const core = require('@actions/core');
const exec = require('@actions/exec');
const os = require('os');

async function run()
{
    const cwd = process.env.RUNNER_TEMP || os.homedir();

    // vc-build ships with rollForward=LatestMajor, so on a runner that has a newer
    // .NET (11+) it runs on that runtime and NUKE fails in NukeBuild's type
    // initializer. Major keeps it on the .NET 10 runtime it targets, and still
    // rolls an app forward when its own major version is not installed.
    // The environment variable overrides the tool's runtimeconfig.json.
    core.exportVariable('DOTNET_ROLL_FORWARD', 'Major');
    process.env.DOTNET_ROLL_FORWARD = 'Major';

    await exec.exec("dotnet --list-sdks");
    await exec.exec('dotnet',
        ['tool', 'install', '--global', 'VirtoCommerce.GlobalTool', '--version', '3.1001.0',
         '--add-source', 'https://api.nuget.org/v3/index.json', '--ignore-failed-sources'],
        { cwd });
    core.addPath('/home/runner/.dotnet/tools/');
}

run().catch(err => core.setFailed(err.message));
