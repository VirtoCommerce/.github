const { describe, test, before, mock } = require('node:test');
const assert = require('node:assert/strict');
const core = require('@actions/core');
const { cleanMessages } = require('./changelog');

const DEVELOPMENT = '🎯 Development';
const IMPROVEMENTS = '📈 Improvements';
const BUG_FIXES = '🐞 Bug fixes';
const CHORE = '🗿 Chore';
const DOCUMENTATION = '📝 Documentation';

// One entry exactly as `git log --pretty=format:"HASH: %h MSG:%Cgreen%s %Creset BODY: %Cred(%b)%Creset"` prints it.
function commit(subject, body = '', hash = 'abc1234') {
    return `HASH: ${hash} MSG:${subject}  BODY: (${body})`;
}

function notes(subject, body) {
    return cleanMessages(commit(subject, body));
}

function section(title, ...lines) {
    return `<h3>${title}</h3><ul>${lines.map(line => `<li>${line}</li>`).join('')}</ul>`;
}

before(() => {
    mock.method(core, 'info', () => { });
});

describe('conventional subject', () => {
    test('plain type: text', () => {
        assert.equal(notes('feat: Add wishlist sharing'), section(DEVELOPMENT, 'Add wishlist sharing'));
        assert.equal(notes('fix: Repair search (#2386)'), section(BUG_FIXES, 'Repair search (#2386)'));
    });

    test('every type lands in its section; ci is not printed', () => {
        const sectionByType = {
            feat: DEVELOPMENT, fix: BUG_FIXES, docs: DOCUMENTATION,
            perf: IMPROVEMENTS, refactor: IMPROVEMENTS, test: IMPROVEMENTS,
            style: CHORE, chore: CHORE, build: CHORE,
        };
        for (const [type, title] of Object.entries(sectionByType)) {
            assert.equal(notes(`${type}: text`), section(title, 'text'), type);
        }
        assert.equal(notes('ci: text'), '');
    });

    test('scoped header drops the scope', () => {
        assert.equal(notes('fix(VCST-4219): add missing reset search elements (#2055)'),
            section(BUG_FIXES, 'add missing reset search elements (#2055)'));
        assert.equal(notes('build(deps): Bump SDK'), section(CHORE, 'Bump SDK'));
    });

    test('breaking header gets the BREAKING prefix', () => {
        assert.equal(notes('feat!: Drop .NET 8 support'), section(DEVELOPMENT, 'BREAKING: Drop .NET 8 support'));
    });

    test('scoped breaking header drops the scope and gets the BREAKING prefix', () => {
        assert.equal(notes('refactor(api)!: Rename IStoreService'), section(IMPROVEMENTS, 'BREAKING: Rename IStoreService'));
    });

    test('BREAKING CHANGE footer marks the commit breaking', () => {
        assert.equal(notes('feat(api): Rename endpoint', 'Details.\n\nBREAKING CHANGE: /api/x is now /api/y'),
            section(DEVELOPMENT, 'BREAKING: Rename endpoint'));
        assert.equal(notes('fix: Rename endpoint', 'BREAKING-CHANGE: old route removed'),
            section(BUG_FIXES, 'BREAKING: Rename endpoint'));
    });

    test('lowercase "breaking change" is not a footer', () => {
        assert.equal(notes('fix: Text', 'not a breaking change: really'), section(BUG_FIXES, 'Text'));
    });
});

describe('skipped subjects', () => {
    const skipped = [
        'revert: feat: Add wishlist sharing',
        'Revert "feat: Add wishlist sharing"',
        'Merge pull request #2391 from VirtoCommerce/feat/ccit-343',
        "Merge branch 'dev' into feat/x",
        '3.84.0',
        'Updating Github Action workflows.',
        'Fix: capitalized type',
        'feat:no space after colon',
        'feature: unknown type',
        'hotfix: not a known type',
        'feat(): empty scope',
    ];

    for (const subject of skipped) {
        test(subject, () => {
            assert.equal(notes(subject, 'fix: text in the body'), '');
        });
    }
});

describe('Jira-key subject', () => {
    test('no markers in body → subject without the key is a feature', () => {
        assert.equal(notes('PT-3771: Provide option to show user-friendly errors (#2378)'),
            section(DEVELOPMENT, 'Provide option to show user-friendly errors (#2378)'));
        assert.equal(notes('#VCST-1: Hash-prefixed key'), section(DEVELOPMENT, 'Hash-prefixed key'));
    });

    test('body starting with a Jira key → feature-style, body markers ignored', () => {
        assert.equal(notes('VCST-10: Add X', 'VCST-10: first step\nfix: second step'), section(DEVELOPMENT, 'Add X'));
    });

    test('single plain marker', () => {
        assert.equal(notes('VCST-2213: Cannot save empty field (#2859)', 'fix: Allow to save empty field'),
            section(BUG_FIXES, 'Allow to save empty field'));
    });

    test('scoped marker drops the scope', () => {
        assert.equal(notes('VCST-1: Subject', 'fix(catalog): Repair search'), section(BUG_FIXES, 'Repair search'));
    });

    test('breaking markers get the BREAKING prefix', () => {
        assert.equal(notes('VCST-1: Subject', 'feat!: Drop A'), section(DEVELOPMENT, 'BREAKING: Drop A'));
        assert.equal(notes('VCST-1: Subject', 'feat!: Drop A\nfeat(api)!: Drop B'),
            section(DEVELOPMENT, 'BREAKING: Drop A', 'BREAKING: Drop B'));
    });

    test('build marker', () => {
        assert.equal(notes('VCST-1: Subject', 'build: Bump SDK'), section(CHORE, 'Bump SDK'));
    });

    test('ci marker is parsed but not printed', () => {
        assert.equal(notes('VCST-1: Subject', 'ci: Update workflows'), '');
    });

    test('several markers keep the last one (CRLF body, VCST-2471)', () => {
        const body = 'fix: Updated npm-shrinkwrap.json to add license info. (#2875)\r\nfix: Updated package.json to include jquery-ui. (#2875)';
        assert.equal(notes('VCST-2471: Update dependencies (#2875)', body), section(BUG_FIXES,
            'Updated npm-shrinkwrap.json to add license info. (#2875)',
            'Updated package.json to include jquery-ui. (#2875)'));
    });

    test('three markers of mixed types', () => {
        assert.equal(notes('VCST-1: Subject', 'feat: A\nfix: B\ndocs: C'),
            section(DEVELOPMENT, 'A') + section(BUG_FIXES, 'B') + section(DOCUMENTATION, 'C'));
    });

    test('a marker right after a word-ending line is still found (LF body)', () => {
        assert.equal(notes('VCST-1: Subject', 'fix: Repair A\nfix: Repair B'), section(BUG_FIXES, 'Repair A', 'Repair B'));
    });

    test('a long first item does not duplicate the next marker', () => {
        const longText = 'long text '.repeat(10).trim();
        assert.equal(notes('VCST-1: Subject', `fix: ${longText}\nfix: B`), section(BUG_FIXES, longText, 'B'));
    });

    test('squash bullets are not part of the item', () => {
        assert.equal(notes('CCIT-343: Fix links (#2391)', '* feat: Fix broken links\n\n* feat: Fix broken links v2'),
            section(DEVELOPMENT, 'Fix broken links', 'Fix broken links v2'));
        assert.equal(notes('VCST-1: Subject', '- fix: A\n- fix: B'), section(BUG_FIXES, 'A', 'B'));
    });

    test('Co-authored-by trailers are not part of the last item (VCST-1917)', () => {
        const body = 'fix: the display of the module icon\r\nfeat: Rename the module menu item\r\n\r\n'
            + 'Co-authored-by: Oleg Zhuk <zhukoo@gmail.com>\r\nCo-authored-by: Kutasina Elena <ekuvirto@users.noreply.github.com>';
        assert.equal(notes('VCST-1917: Make module management blades similar (#2844)', body),
            section(DEVELOPMENT, 'Rename the module menu item') + section(BUG_FIXES, 'the display of the module icon'));
        assert.equal(notes('VCST-1: Subject', 'fix: A\n\nSigned-off-by: Dev <dev@example.com>'), section(BUG_FIXES, 'A'));
    });

    test('a body ending in "(#2876)" keeps its paren (VCST-2486)', () => {
        assert.equal(notes('VCST-2486: Add LocalizedString class (#2876)', 'feat: Introduce LocalizedString class.  (#2876)'),
            section(DEVELOPMENT, 'Introduce LocalizedString class. (#2876)'));
    });

    test('words ending in a type are not markers', () => {
        assert.equal(notes('VCST-1: Subject', 'Applied a hotfix: and a pre-fix: here'), section(DEVELOPMENT, 'Subject'));
        assert.equal(notes('VCST-1: Subject', 'fix: Use the latest: version'), section(BUG_FIXES, 'Use the latest: version'));
    });

    test('empty items are dropped', () => {
        assert.equal(notes('VCST-1: Subject', 'fix: \nfix: B'), section(BUG_FIXES, 'B'));
    });
});

describe('cleanMessages', () => {
    test('no commits → empty string', () => {
        assert.equal(cleanMessages(''), '');
    });

    test('sections in order, types grouped, build next to style and chore', () => {
        const log = [
            commit('docs: Update README'),
            commit('build: Bump SDK'),
            commit('chore(deps): Update packages'),
            commit('style: Format code'),
            commit('fix(api)!: Change error codes'),
            commit('test: Add tests'),
            commit('refactor: Simplify parser'),
            commit('perf: Cache lookups'),
            commit('feat: Add sharing'),
            commit('ci: Update workflows'),
            commit('Merge pull request #1 from VirtoCommerce/dev'),
            commit('revert: feat: Add sharing'),
        ].join('\n');

        assert.equal(cleanMessages(log),
            section(DEVELOPMENT, 'Add sharing')
            + section(IMPROVEMENTS, 'Cache lookups', 'Simplify parser', 'Add tests')
            + section(BUG_FIXES, 'BREAKING: Change error codes')
            + section(CHORE, 'Format code', 'Update packages', 'Bump SDK')
            + section(DOCUMENTATION, 'Update README'));
    });

    test('legacy test-page fixture renders as before', () => {
        // The sample from the former test-page.html, indentation included.
        const log = `HASH: 32734a33e MSG:Feat/ccit 343 (#2391)  BODY: (* feat: Fix broken links

                * feat: Fix broken links v2)
                HASH: 1d4f01b0d MSG:CCIT-343: Migrate lesson 1 for Platform 3 (#2379)  BODY: (* CCIT-343: Migrate lesson 1 for Platform 3

                * CCIT-343: PR review fix)
                HASH: 4b300d03a MSG:3.84.0  BODY: ()
                HASH: e21a8d94f MSG:fix: Azure assets: repair search by keyword for folders in the root  BODY: ()
                HASH: 3a694336c MSG:fix: Fix an error in absolute URI checker (#2386)  BODY: ()
                HASH: 431a6ec99 MSG:Fixed misspeling (#2387)  BODY: (fix: Fixed wrong value for License Type on platform information blade, if the license is activated.)
                HASH: 84331cbe4 MSG:Added News Digests  BODY: ()
                HASH: 4cb2db85c MSG:PT-0: Improve a type incompatibility exception message for the changes detector  BODY: ()
                HASH: 0884f098b MSG:Updating Github Action workflows.  BODY: ()
                HASH: 4666aaa61 MSG:PT-3771: Provide option to show user-friendly errors (#2378)  BODY: (* PT-3771: Provide option to show user-friendly errors

                * PT-3771: Suppressing stack traces for non-development environments

                * PT-3771: Fix bug)`;

        assert.equal(cleanMessages(log),
            section(DEVELOPMENT,
                'Migrate lesson 1 for Platform 3 (#2379)',
                'Improve a type incompatibility exception message for the changes detector',
                'Provide option to show user-friendly errors (#2378)')
            + section(BUG_FIXES,
                'Azure assets: repair search by keyword for folders in the root',
                'Fix an error in absolute URI checker (#2386)'));
    });
});
