# Project conventions

Sonoglitch is a Flutter camera app (Android first, iOS from the same code base).
See `docs/SPEC.es.md` for the product specification (in Spanish).

## Rules

- **Privacy first.** Never record, store or transmit audio: read the volume level in memory only. No accounts, servers, analytics or network calls in the app.
- **Dependencies.** Add one only with a reason. Prefer maintained packages with a permissive licence (Apache-2.0, MIT or BSD); check it before adding.
- **No secrets** in the repository: no keys, keystores, tokens, `.env` files or personal paths.
- **Language.** Code, comments, commit messages and documentation in English.
- **Changelog.** Every change the user notices is added to `CHANGELOG.md` (section "Unreleased") in the same commit. The changelog is written in English, for the user; numbering and channels are in `docs/RELEASING.md` (Versionado y trazabilidad).
- **Commits.** [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `chore:`, `docs:`, `test:`), small and focused, no WIP commits on `main`.
- **Effects.** Every style exposes the same three controls with unchanged semantics: noise controls disturbance intensity, light controls tone and contrast, and motion controls movement and trails. Additional signals may only provide bounded signature modulations of pattern, scale, orientation, texture and palette; they must not replace these controls or exceed the combined distortion budget. A per-capture micro-fingerprint may remain at neutral controls, bounded to one 8-bit code value per channel. Geometry must use normalized, aspect-correct coordinates. Preview and still rendering must share the same contract, with capture parameters frozen once at the shutter.

## Commands

```sh
flutter pub get
dart format .
flutter analyze
flutter test
```

All of `dart format --output=none --set-exit-if-changed .`, `flutter analyze` and `flutter test` must pass before a change is merged.
