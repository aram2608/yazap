# chizel — Code Review

## Proposed New Features

### Feature 2: Config-file fallback layer

Extend the value-resolution chain to:

```
CLI flag  >  environment variable  >  config file  >  default
```

A new optional field on `ArgParser`:

```zig
try parser.loadConfig("/etc/myapp/config"); // or ~/.myapprc
```

The config file format would be a simple `key=value` text file (one option per line), easy to parse without pulling in a TOML/JSON dependency. Keys map to option names; values are parsed with the same `parseEnvValue` logic already in the parser.

Benefits:
- No change to the existing API (loadConfig is opt-in).
- Consistent with the existing env-var semantics (same parsing rules).
- Lets tools ship a system-wide default config distinct from the Zig defaults.

---

### Feature 3: Shell completion script generation

IN PROGRESS

Add a method `writeCompletions(shell, writer)` that emits a completion script for bash, zsh, or fish using only the already-registered option metadata (names, short flags, tags, help text):

```zig
try parser.writeCompletions(.zsh, std.fs.File.stdout().writer());
```

The generated script would register all long and short flags, add type hints (`<int>`, `<string>`, etc.) as completion descriptions, and mark boolean flags as no-argument completions.

This is achievable without external dependencies because all the required metadata (option names, shorts, tags, help strings, required flags) is already stored in `option_order` and `options`. The feature requires no new parsing logic — only a new output path — making it a low-risk, high-value addition for any tool built on chizel.
