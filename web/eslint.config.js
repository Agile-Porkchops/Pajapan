import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import tseslint from 'typescript-eslint'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      globals: globals.browser,
    },
    rules: {
      // Mechanical enforcement of the no-RLS decision (spec §5.1): the
      // supabase client in lib/supabase.ts is auth-only. Every data read and
      // write goes through the API, which is the sole holder of a DB
      // credential. Without this, the constraint decays the first time
      // someone reaches for .from() in a hurry.
      'no-restricted-properties': ['error',
        { object: 'supabase', property: 'from', message: 'Use the API (lib/apiClient.ts), not Supabase, for data access — see spec §5.1.' },
        { object: 'supabase', property: 'rpc', message: 'Use the API (lib/apiClient.ts), not Supabase, for data access — see spec §5.1.' },
      ],
    },
  },
  {
    // shadcn-generated primitives export a component plus a `*Variants`
    // helper from one file by convention — that's the library's shape, not
    // ours to refactor, so the fast-refresh export rule doesn't apply here.
    files: ['src/components/ui/**/*.{ts,tsx}'],
    rules: {
      'react-refresh/only-export-components': 'off',
    },
  },
])
