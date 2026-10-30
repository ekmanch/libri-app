import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/operations/library_operation.dart';
import 'package:library_app/data/operations/settings_operations.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/data/repository/library_repository.dart';

/// A repository whose [apply] publishes the change and then keeps the caller
/// waiting, like the GitHub one does while it writes its queue and cache to
/// disk. Frames run in between, so a screen that watches the library sees
/// the change before the caller's code after the await runs. The default
/// delay is shorter than a sheet's closing animation, as on a device, so
/// the caller resumes while the sheet is still on its way out.
class SlowSaveRepository implements LibraryRepository {
  SlowSaveRepository(
    this.inner, {
    this.delay = const Duration(milliseconds: 50),
  });

  final FixtureLibraryRepository inner;
  final Duration delay;

  @override
  Future<Library> load() => inner.load();

  @override
  Stream<Library> watch() => inner.watch();

  @override
  Future<Library> apply(LibraryOperation operation) async {
    final next = await inner.apply(operation);
    await Future<void>.delayed(delay);
    return next;
  }

  @override
  Future<AppSettings> loadSettings() => inner.loadSettings();

  @override
  Stream<AppSettings> watchSettings() => inner.watchSettings();

  @override
  Future<AppSettings> applySettings(SettingsOperation operation) =>
      inner.applySettings(operation);
}
