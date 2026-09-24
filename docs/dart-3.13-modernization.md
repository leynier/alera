# Dart 3.13 modernization

Alera's own Dart packages require Dart 3.13.2. Flutter remains pinned to 3.47.2, including the Linux Skia setting and iOS 15 deployment target established in the Flutter upgrade. This is a source modernization, not a change to runtime protocols, storage schemas, platform toolchains or distribution.

## Package and generator compatibility

The existing analyzer 12.1.0 recognizes primary-constructor syntax but still treats it as experimental. The isolated compatibility probe failed with all three generators on that stack. Analyzer 13.3.0 enables the released language feature without experimental flags.

The compatible minimum generator stack uses Riverpod generator 4.0.7, annotation 4.0.5, Flutter Riverpod 3.4.1, Riverpod lint 3.1.7, dart_mappable_builder 4.9.0 and drift_dev 2.34.1+1. Build runner 2.15.1, runtime dart_mappable 4.8.0 and runtime Drift 2.34.3 remain unchanged. Riverpod generator 4.0.6 was rejected by the dependency solver because its analyzer-utils dependency still required analyzer 12. Lockfiles retain unrelated package versions.

The standalone runtime packager manifest now lives under `tool/release/runtime_packager`. Its CI command resolves that package and supplies its package configuration explicitly when running the existing `package_runtime_sidecars.dart` entrypoint. Keeping the minimal manifest outside the other release scripts prevents it from shadowing their application dependencies during analysis. The packager remains usable with a Dart-only toolchain; commands, archive formats and signing behavior are unchanged.

## Source conventions

Use primary constructors when they remove repeated declarations while preserving public argument names, `const`, defaults, annotations and initialization behavior. Retain traditional constructors when multiple generative constructors or generator limitations require them. Concise in-body constructors are appropriate where a primary constructor is not.

Use dot shorthands only when the expected type is clear. Private initializing parameters, super parameters, null-aware collection elements and patterns should simplify equivalent code, not change parser fallbacks or exception behavior. `Future.pause` replaces only waits without callbacks; it does not turn event-loop waits into microtasks. Typed `unmodifiableOf` constructors preserve copying and immutability.

Generated files are regenerated, not manually modernized. Keep explicit fields in mapped models when converting them to declaring parameters would reorder generated serialization keys. Preserve comments and annotations when applying automated assists. Measurement harnesses retain their behavior so before/after performance samples remain comparable.

Do not replace asynchronous isolates with the new synchronous APIs on the UI isolate. Do not remove `async` or `await` mechanically: exception delivery, error handling and scheduling are observable behavior.

## Validation record

The baseline is main commit `49355a781f99bb919361118535d51a83f3444398`, using the same Flutter 3.47.2 / Dart 3.13.2 SDK with language 3.12. Desktop and mobile analysis found no issues. Desktop tests passed 3,408 cases with one integration-only skip; mobile passed 629 with three relay integration-only skips.

The isolated generator probe passes JSON field annotations, inherited defaults, constant identity and `copyWith`, a Riverpod family with default arguments, and an in-memory Drift table with its schema and default value. The old generator failure and the successful compatible run are retained as local evidence.

The initial performance series is not acceptance evidence: unrelated Flutter tests and native compilation raised host load sharply and materially changed frame times. The raw samples and baseline source are preserved for a matched comparison. Build, performance and final review results are recorded in [PR #593](https://github.com/leynier/alera/pull/593), together with the tested commit identities.

Language references: [primary constructors](https://dart.dev/language/primary-constructors), [constructor syntax](https://dart.dev/language/constructors#concise-constructor-syntax), and [Dart 3.13.2 changelog](https://github.com/dart-lang/sdk/blob/3.13.2/CHANGELOG.md).

## Transformation review and exceptions

The review covers tracked own production code, tools, tests and previews. Primary constructors and declaring parameters remove repeated declarations; concise constructors retain multiple-constructor and redirecting designs. Explicit field declarations remain in mapped models to preserve serialization order, and field documentation and annotations are retained. Existing super parameters are preserved, with the generated Drift compatibility fixture also exercising primary super parameters.

Dot shorthands use a concrete expected type. Keep explicit types where a generic call must infer its own type argument, such as `Navigator.pop` and an untyped `_guarded` fallback, and in map indexing because its key parameter is `Object?`. Process-spawn and loopback conformance guards retain their explicit `ProcessStartMode.detached` and `InternetAddress.loopbackIPv4` references. Unnamed widget constructors remain explicit so widget trees retain their component names.

Null-aware entries preserve omission of optional serialized fields in browser and mobile payloads. Configuration parsers use type patterns while retaining map-key casts, invalid-schema errors, scalar fallbacks, null values and list order. Existing asynchronous isolate, process and native boundaries remain unchanged. Benchmark harnesses receive formatting only.

The playback monitor regression test now drives stream delivery and retry timers with `fake_async`; it no longer races a real one-millisecond timer under host load. It retains the original recovery and disposal assertions. New compatibility tests cover annotated primary enums and models, inherited defaults, constant identity, generated JSON and `copyWith`, Riverpod family defaults, Drift row defaults, immutable application snapshots and zero/nonzero event-loop pauses.

Callback-bearing `Future.delayed` calls and `Set.unmodifiable` remain unchanged. Callback-free `Future<void>` waits use `Future.pause`; list and map snapshots use `unmodifiableOf` with compatible typed inputs, including iterable inputs from native-helper validation. No casts were added to force incompatible inputs through the new APIs.
