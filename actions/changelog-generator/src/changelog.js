const core = require('@actions/core');

function cleanMessages(messages) {
    let jiraTasksRegex = /^#*[A-Z]{2,5}-\d{1,5}:{0,1}\s*/mi;

    const releaseNoteGroups = [
        { key: "feat", items: [] },
        { key: "fix", items: [] },
        { key: "docs", items: [] },
        { key: "style", items: [] },
        { key: "refactor", items: [] },
        { key: "perf", items: [] },
        { key: "test", items: [] },
        { key: "build", items: [] },
        { key: "ci", items: [] },
        { key: "chore", items: [] },
    ]

    // Conventional Commits header: "type: ", "type(scope): ", "type!: " or "type(scope)!: "
    const typePattern = "(" + releaseNoteGroups.map(group => group.key).join("|") + ")(?:\\([^()]+\\))?(!)?:\\s";
    const subjectTypeRegex = new RegExp("^" + typePattern);
    // In a body, a marker starts a word: "hotfix: " is not "fix: "
    const bodyTypeRegex = new RegExp("(?<![\\w-])" + typePattern, "g");
    const breakingPrefix = "BREAKING: ";

    // Collect messages in groups
    messages.split('HASH:')
        .forEach(commitMsg => {
            const oneLineMsg = commitMsg.replaceAll("\n", " ") // Replace newlines
                .replace(/\s+/g, ' ')       // Replace multiple spaces with a single space
                .trim() // Trim any leading/trailing spaces

            // Skip empty lines
            if (oneLineMsg === "") { return; }
            core.info(`Raw -> ${oneLineMsg}`);

            const msgAndBody = oneLineMsg.split('BODY:');
            const msg = msgAndBody[0].split('MSG:')[1].trim();
            const body = msgAndBody[1].trim()
                .replace(/^\s*\(/, '') // Remove the "(%b)" wrapper: one paren each side,
                .replace(/\)\s*$/, '') // so a body ending in "(#2876)" keeps its own
                .replace(/\s*\b(Co-authored-by|Signed-off-by): .*$/, ''); // Remove git trailers at the end

            // Example message (PT-3771: Provide option to show user-friendly errors) 
            if (jiraTasksRegex.test(msg)) {

                // Feature-style commit
                if (jiraTasksRegex.test(body)) {
                    const message = msg.replace(jiraTasksRegex, '');

                    core.info(`FEAT -> ${message}`);
                    releaseNoteGroups[0].items.push(message);
                    core.info("----------");

                    return;
                }

                const groupIndexes = [...body.matchAll(bodyTypeRegex)].map(match => ({
                    key: match[1],
                    index: match.index,
                    template: match[0],
                    prefix: match[2] ? breakingPrefix : '',
                }));

                // Only text in body message => use message as source of truth
                if (groupIndexes.length === 0) {
                    const message = msg.replace(jiraTasksRegex, '');

                    core.info(`FEAT -> ${message}`);
                    releaseNoteGroups[0].items.push(message);
                    core.info("----------");

                    return;
                }

                // One match
                if (groupIndexes.length === 1) {
                    let key = groupIndexes[0].key;
                    const message = groupIndexes[0].prefix + body.replace(groupIndexes[0].template, '');

                    core.info(`${key.toUpperCase()} -> ${message}`);
                    releaseNoteGroups.find(group => group.key === key).items.push(message);
                    core.info("----------");

                    return;
                }

                // Sort by position
                groupIndexes.sort((indexGroupA, indexGroupB) => indexGroupA.index - indexGroupB.index);

                for (let i = 0; i < groupIndexes.length; i++) {
                    const message = groupIndexes[i].prefix + body
                        .substring(groupIndexes[i].index, groupIndexes[i + 1]?.index) // the last marker runs to the end
                        .replace(groupIndexes[i].template, '')
                        .trim()
                        .replace(/\s+[*-]$/, ''); // Remove the bullet of the next squashed commit

                    core.info(`${groupIndexes[i].key.toUpperCase()} -> ${message}`);
                    releaseNoteGroups.find(group => group.key === groupIndexes[i].key).items.push(message);
                    core.info("----------");
                }
            }
            else if (subjectTypeRegex.test(msg)) {
                const header = msg.match(subjectTypeRegex);
                const isBreaking = !!header[2] || /(^|\s)BREAKING[ -]CHANGE: /.test(body); // "!" or the footer

                releaseNoteGroups.forEach(group => {
                    if (header[1] !== group.key) { return; }
                    const message = (isBreaking ? breakingPrefix : '') + msg.replace(header[0], '');

                    core.info(`${group.key.toUpperCase()} -> ${message}`);
                    group.items.push(message);
                    core.info("----------");
                })
            }
            else {
                // Skip commits without Jira-keys and commit pattern in the start
                core.info("SKIP");
                core.info("----------");

                return;
            }
        });

    // Build release-note string
    function generateGroup(title, items) {
        let result = `<h3>${title}</h3>`;
        result += "<ul>"
        items.filter(function (e) { return !!e }).forEach(item => result += `<li>${item}</li>`);
        result += "</ul>"

        return result;
    }

    let result = "";

    // Development
    const developmentItems = releaseNoteGroups.find(group => group.key === "feat").items;
    if (developmentItems.length > 0) {
        result += generateGroup("🎯 Development", developmentItems);
    }

    // Improvements (perf + refactor + test)
    const improvementItems = [
        ...releaseNoteGroups.find(group => group.key === "perf").items,
        ...releaseNoteGroups.find(group => group.key === "refactor").items,
        ...releaseNoteGroups.find(group => group.key === "test").items,
    ];
    if (improvementItems.length > 0) {
        result += generateGroup("📈 Improvements", improvementItems);
    }

    // Fixes
    const fixesItems = releaseNoteGroups.find(group => group.key === "fix").items;
    if (fixesItems.length > 0) {
        result += generateGroup("🐞 Bug fixes", fixesItems);
    }

    // Chore (style + chore + build)
    const choreItems = [
        ...releaseNoteGroups.find(group => group.key === "style").items,
        ...releaseNoteGroups.find(group => group.key === "chore").items,
        ...releaseNoteGroups.find(group => group.key === "build").items
    ];
    if (choreItems.length > 0) {
        result += generateGroup("🗿 Chore", choreItems);
    }

    // Documentation
    const docsItems = releaseNoteGroups.find(group => group.key === "docs").items;
    if (docsItems.length > 0) {
        result += generateGroup("📝 Documentation", docsItems);
    }

    core.info(`Result: ${result}`);

    return result;
}

module.exports = { cleanMessages };
