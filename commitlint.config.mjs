// Commit messages must follow Conventional Commits — release-please parses
// them to build the CHANGELOG and decide version bumps. A commit that fails
// this lint would be silently dropped from the release notes.
// Types mirror the changelog-sections in release-please-config.json.
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      [
        'feat',
        'fix',
        'perf',
        'refactor',
        'docs',
        'chore',
        'build',
        'ci',
        'style',
        'test',
        'revert',
      ],
    ],
  },
};
