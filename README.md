# vaffected

Run only the tests a change can actually affect.

Fast debug-test loops waste most of their time re-running tests the change
cannot touch. `vaffected` closes that gap: feed it what changed and it
returns the `*_test.v` files that transitively depend on those source files,
via a static scan of every V file's imports — deterministic, change-size
independent, and capped by saying nothing rather than guessing.

Written in V. Pure V (no subprocesses in the library), same philosophy as
[vrepo](https://github.com/gil-silva/vrepo) and
[v-mcp-server](https://github.com/gil-silva/v-mcp-server). MIT.

## How it works

1. Scan every `.v` file under the project root; parse its `module` and
   `import` lines (comments ignored) into a file → package-key map. A
   package key is the file's directory path, dotted: `sub/util` → `'sub.util'`;
   root-level files share the synthetic `'main'` key (module `main` is
   unimportable, so it can never gain dependents).
2. Seed the affected set with the changed files' keys.
3. Propagate backwards: any file importing an affected in-tree package
   becomes affected, so its own package joins the set; repeat until stable.
   Imports with unknown leading segments (`import gil_silva.vrepo.vrepo`)
   still match in-tree packages via dotted-suffix lookup; ambiguous targets
   resolve to every candidate — conservative by construction.
4. Intersect with `*_test.v` and print, one sorted path per line.

## CLI

```bash
mkdir -p bin && v -no-parallel -o bin/vaffected .   # build from source
bin/vaffected [root] [base]                          # defaults: '.', 'HEAD'
```

Changed input comes from `git diff --name-only <base>` — uncommitted or
committed-to-`base` changes alike. Empty result prints
`no affected tests (nothing to re-run)` so pipe users still have a signal:

```bash
bin/vaffected . HEAD~1     # tests touched by the last commit
bin/vaffected testdata | head    # never scans fixture data by default
bin/vaffected --run        # straight to `v test` on the affected files,
                           # propagating its exit code
```

## Library

The same machinery is importable as `vaffected`:

```v
import vaffected

report := vaffected.affected_report(root, changed_paths)!
files := vaffected.collect_files(root)!
```

## Roadmap

- `--run`: pass the affected files straight to `v test`
- an MCP tool peer of `v_repo_brief` in the `vlang` server once stable
