const core = require('@actions/core');
const github = require('@actions/github');
const exec = require('@actions/exec');
const fs = require('fs');
const utils = require('@virtocommerce/vc-actions-lib');
const { cleanMessages } = require('./src/changelog');

async function getCommitMessages(since) {
    const format = "HASH: %h MSG:%Cgreen%s %Creset BODY: %Cred(%b)%Creset";

    let output = '';
    const options = {
        listeners: {
            stdout: (data) => {
                output += data.toString();
            },
            stderr: (data) => {
                core.info(data.toString());
            }
        }
    }

    await exec.exec(`git log --pretty=format:"${format}" --since="${since}"`, [], options)
        .then(exitCode => core.info(`git log --pretty=format:"${format}" --since exitCode: ${exitCode}`));

    return output.trim();
}

async function run() {
    let isDependencies = await utils.isDependencies(github);
    if (isDependencies) {
        core.info(`Pull request contain "dependencies" label. Step skipped.`);
        return;
    }

    let latestRelease = await utils.getLatestRelease(process.env.GITHUB_REPOSITORY);
    let commitMessages = "";
    if (latestRelease != null) {
        commitMessages = await getCommitMessages(latestRelease.published_at);
        commitMessages = cleanMessages(commitMessages);
    }

    core.info(commitMessages);
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `changelog=${commitMessages}\n`);
}

run().catch(err => {
    core.setFailed(err.message);
});
