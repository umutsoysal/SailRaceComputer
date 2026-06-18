# Contributing to Race Mate

Thanks for contributing to SailRaceComputer.

## Local setup

1. Install Flutter stable and verify with `flutter --version`.
2. Install dependencies: `flutter pub get`.
3. Run static checks: `flutter analyze`.
4. Run tests: `flutter test`.
5. Run the app:
   - Production entry: `flutter run`
   - Simulator entry: `flutter run -t lib/dev/sim_main.dart -d chrome`

## Branch and commit guidance

- Create feature branches from `main`.
- Keep pull requests focused and reasonably small.
- Use clear commit messages in imperative mood.
- Rebase or merge `main` before requesting review if your branch is stale.

## Code quality standards

- Keep code formatted with `dart format`.
- Add or update tests when behavior changes.
- Preserve existing architecture patterns (`models`, `services`, `utils`, `screens`).
- Validate course file format changes with tests in `test/course_file_test.dart`.
- Validate navigation math changes with tests in `test/geo_test.dart`.

## Pull request expectations

Before opening a PR, ensure:

- `flutter analyze` passes.
- `flutter test` passes.
- Relevant documentation is updated.
- Screenshots or short notes are provided for UI changes.

PRs use the built-in template to keep reviews consistent.

## Security

For vulnerabilities, follow the process in [SECURITY.md](.github/SECURITY.md) instead of filing a public issue.
