import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;

import '../library_codec.dart';
import '../models/app_settings.dart';
import '../models/library.dart';
import '../operations/library_operation.dart';
import '../operations/settings_operations.dart';
import 'library_repository.dart';

/// Loads `assets/fixtures/library.json` and keeps every change in memory
/// only. Nothing is ever written anywhere. The settings start as the
/// defaults (or [settings]) and stay in memory too.
class FixtureLibraryRepository implements LibraryRepository {
  FixtureLibraryRepository({
    Future<String> Function()? loadJson,
    AppSettings settings = AppSettings.defaults,
  }) : _loadJson = loadJson ?? _loadAsset,
       // ignore: prefer_initializing_formals
       _settings = settings;

  static const assetPath = 'assets/fixtures/library.json';

  static Future<String> _loadAsset() => rootBundle.loadString(assetPath);

  final Future<String> Function() _loadJson;
  final _changes = StreamController<Library>.broadcast();
  final _settingsChanges = StreamController<AppSettings>.broadcast();
  Future<Library>? _loading;
  Library? _library;
  AppSettings _settings;

  @override
  Future<Library> load() async {
    if (_library != null) return _library!;
    _loading ??= _loadJson().then(decodeLibrary);
    final loaded = await _loading!;
    // An apply may have run while the file was loading; keep its result.
    return _library ??= loaded;
  }

  @override
  Stream<Library> watch() async* {
    yield await load();
    yield* _changes.stream;
  }

  @override
  Future<Library> apply(LibraryOperation operation) async {
    await load();
    // Read after the await: another change may have landed meanwhile.
    final next = operation.apply(_library!);
    _library = next;
    _changes.add(next);
    return next;
  }

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Stream<AppSettings> watchSettings() async* {
    yield _settings;
    yield* _settingsChanges.stream;
  }

  @override
  Future<AppSettings> applySettings(SettingsOperation operation) async {
    final next = operation.apply(_settings);
    if (next == _settings) return next;
    _settings = next;
    _settingsChanges.add(next);
    return next;
  }

  /// The current in-memory library, if loaded.
  Library? get current => _library;

  /// The current in-memory settings.
  AppSettings get currentSettings => _settings;

  void dispose() {
    _changes.close();
    _settingsChanges.close();
  }
}
