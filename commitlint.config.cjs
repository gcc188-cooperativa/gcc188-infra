// Conventional Commits com o componente como escopo, ex.: fix(proxy): corrigir CSP (RNF-19)
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [2, 'always', ['proxy', 'front', 'backend', 'db', 'backup', 'compose', 'e2e', 'perf', 'observabilidade', 'scripts', 'versoes', 'ci', 'deps', 'docs']],
    'header-max-length': [2, 'always', 100],
  },
};
