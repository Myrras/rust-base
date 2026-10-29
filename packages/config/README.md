# @myrras/rust-base-config

Shared frontend tooling config for apps built from
[rust-base](https://github.com/Myrras/rust-base) (Tauri 2 + React +
Vite): ESLint, Prettier and TypeScript.

## Install

```sh
pnpm add -D @myrras/rust-base-config eslint prettier typescript
```

`eslint`, `prettier` and `typescript` are peer dependencies: the app keeps them
as its own devDependencies so `pnpm lint`, `pnpm format` and `tsc` can run their
binaries. The ESLint plugins (`@eslint/js`, `typescript-eslint`,
`eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`, `globals`) come with
this package; the app does not declare them.

## Usage

`eslint.config.js`:

```js
export { default } from "@myrras/rust-base-config/eslint";
```

To add app-specific ignores or rules, spread it:

```js
import base from "@myrras/rust-base-config/eslint";

export default [...base, { ignores: ["generated"] }];
```

`.prettierrc.json`:

```json
"@myrras/rust-base-config/prettier"
```

`tsconfig.json` (`include` and `references` stay in the app: paths in an
extended config resolve against the package, not the app):

```json
{
  "extends": "@myrras/rust-base-config/tsconfig.json",
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

`tsconfig.node.json`:

```json
{
  "extends": "@myrras/rust-base-config/tsconfig.node.json",
  "include": ["vite.config.ts"]
}
```

`.prettierignore` is not part of the package: Prettier has no shared ignore
file, so each repo keeps its own.

## Versioning

SemVer, independent of the rust-base CI tags (`v2`). A new major of ESLint,
Prettier or TypeScript in the peer ranges, or a new lint rule that fails
existing code, is a major. Releases are tagged `config-vX.Y.Z` and published
from CI with npm provenance.

## License

MIT.
