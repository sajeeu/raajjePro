// @ts-check
import eslint from '@eslint/js';
import prettier from 'eslint-config-prettier';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: ['dist/', 'node_modules/', 'src/generated/', 'coverage/'],
  },
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // Money is integer laari and ids are UUIDs — a stray `any` is how a float
      // or a numeric id slips through the type system unnoticed.
      '@typescript-eslint/no-explicit-any': 'error',
      // Every promise is awaited or explicitly voided; a dropped rejection in a
      // job or a handler is a silent failure.
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/consistent-type-imports': 'error',
      // Unused parameters prefixed with `_` are a deliberate signature match.
      // ignoreRestSiblings allows the `const { KEY: _omit, ...rest } = obj`
      // idiom for building an object with one key removed.
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', ignoreRestSiblings: true },
      ],
    },
  },
  {
    // Tool configs are plain JS and outside tsconfig; type-aware rules do not apply.
    files: ['**/*.js'],
    ...tseslint.configs.disableTypeChecked,
  },
  // Must be last: switches off every formatting rule Prettier owns.
  prettier,
);
