# Development

How the repository is laid out, how to run and test each part, how CI and releases work, and what a contribution needs.

## Repository layout

| Path | What it is | Guide |
|---|---|---|
| `backend/` | FastAPI server, ASR engines (faster-whisper, parakeet.cpp), auth and security | [backend/README.md](../backend/README.md) |
| `flutter_client/` | The Windows desktop app | [flutter_client/README.md](../flutter_client/README.md) |
| `terminal_client/` | The Python terminal client for Windows | [terminal_client/README.md](../terminal_client/README.md) |
| `scripts/` | Version bumper, benchmarks, SonarQube scan | [Benchmarks](benchmarks/README.md) |
| `docs/` | These guides, release notes, changelog, benchmarks | |
| `setup.sh`, `docker-compose*.yml` | Server quick start and deployment | [Setup](setup.md) |

## Backend

Develop on Linux or WSL with Python 3.12 and [uv](https://docs.astral.sh/uv/):

```bash
./setup.sh --dev          # or, by hand:
cd backend
uv sync --group dev --extra whisper   # Whisper runs in-process
uv sync --group dev                   # Parakeet runs in its own container
```

Quality gates, locally:

```bash
cd backend
uv run pyright .
uv run pytest tests
```

Or inside the running container, which is how the read-only, hardened runtime is tested:

```bash
docker compose exec backend python -m pytest tests/
```

Some infrastructure tests expect the container (a read-only root, `/tmp` as the only writable path), so they fail outside it.

## Flutter client

Windows 10/11 with Flutter 3.50+ (Dart 3.14). Copy `flutter_client/env.json.template` to `env.json` and fill in the OIDC values, then:

```bash
cd flutter_client
flutter pub get
flutter run -d windows --dart-define-from-file=env.json
```

CI runs `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze` and `flutter test`. Run [DCM](https://dcm.dev) locally too (`dcm analyze lib test`); its rules (one widget per file, no magic numbers, …) are configured in `analysis_options.yaml`.

`flutter test test/live` runs a few checks against OpenRouter itself (a fraction of a cent); they are skipped unless `OPENROUTER_API_KEY` is set, so CI never runs them. Run them before a release.

Code is split into `controllers/`, `logic/` (pure, no I/O), `services/` and `ui/`; see the [client guide](../flutter_client/README.md) for the layout and design rules.

## Terminal client

```bash
cd terminal_client
uv sync --group dev
uv run ruff check . && uv run pyright && uv run pytest
```

## Pre-commit hooks

Install once from the repository root:

```bash
uvx pre-commit install
uvx pre-commit run --all-files    # on demand
```

They run Ruff (fix, then format) for `backend/` and `terminal_client/` with each project's own config, and reject merge markers, invalid YAML/TOML/JSON, private keys, files over 2 MB, and version drift between the files `scripts/bump_version.py` manages.

## CI/CD

GitHub Actions run on every push; each workflow runs only when its part changes.

| Workflow | Runner | Checks |
|---|---|---|
| **Pre-commit** | Ubuntu | Every pre-commit hook on every file |
| **Backend** | Ubuntu | Pyright and pytest. Builds the Whisper and Parakeet images, runs `./setup.sh --cpu --yes` as a newcomer would and waits for `/health`, then runs the Whisper image on CPU (`tiny.en`) with the production isolation flags: transcribes `assets/jfk.flac`, asserts the 401 / 411 / 404 rejections and the read-only root, and runs the live API and WebSocket tests |
| **Terminal client** | Windows | Pyright and pytest |
| **Flutter client** | Windows | `dart format`, `flutter analyze`, `flutter test`, and a release build |
| **Release** | Windows | On a `vX.Y.Z` tag: checks versions, release notes and mainline ancestry, builds the obfuscated installer, and creates a **draft** GitHub Release |

Actions are pinned to commit SHAs; Dependabot updates them monthly.

**Repository secrets** (Settings → Secrets and variables → Actions):

- `FLUTTER_ENV_JSON` (required for releases): the contents of `flutter_client/env.json`.
- `SYMBOLS_PASSPHRASE` (optional): attaches the debug symbols as an encrypted `.7z`, so crash traces from CI builds can be deobfuscated.

## Releases

1. `python scripts/bump_version.py <patch|minor|major>` (try `--dry-run` first).
2. Write `docs/release_notes/vX.Y.Z.md` (upgrade notes first) and the `docs/CHANGELOG.md` entry.
3. Commit, then push a signed tag:
   ```bash
   git tag -s vX.Y.Z -m "Release vX.Y.Z - <theme>"
   git push origin mainline vX.Y.Z
   ```
4. Review the draft on the Releases page and publish it. Installed clients learn about updates from `releases/latest`, which ignores drafts, so nobody is prompted until you publish.

Installers are built by CI only; never commit them.

## Contributing

- **Open an issue first** for anything bigger than a fix, so the approach can be agreed before the work.
- **Keep the gates green**: tests, analyzers and formatters above, for every part you touch. New behaviour comes with tests; a bug fix with a test that failed before it.
- **Defaults come with evidence.** A change to a style's prompt, the default speech or rewrite model, or the routing includes a run of the matching [benchmark](benchmarks/README.md).
- **Keep the layers apart** (UI, controllers, logic, services), keep files small and single-purpose, and leave no dead code; write a `TODO` for a known gap instead.
- **Never commit secrets** (`.env`, `env.json`, API keys) or build output. Text files use LF line endings (`.gitattributes` enforces it).
- **Commits are signed** and their messages follow `type: Sentence case summary` ([Conventional Commits](https://www.conventionalcommits.org) types), with a body that lists each change by the part of the project it belongs to.
- Lessons from past mistakes are in [lessons learned](lessons_learned_and_anti_patterns.md); the bigger migrations are written up, e.g. [Parakeet: NeMo to parakeet.cpp](PARAKEET_NEMO_TO_CPP_MIGRATION.md).
