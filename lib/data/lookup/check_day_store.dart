import '../storage/json_file.dart';

/// The day a once-a-day check last ran, kept on the device (never in
/// `library.json`), so the check runs on the first app open of each day
/// and on each return to the foreground until it has run that day.
abstract class CheckDayStore {
  Future<DateTime?> lastRun();

  Future<void> recordRun(DateTime day);
}

/// A JSON file under the cache folder, `{"checked": "2026-10-29"}`. A
/// cleared cache only means one extra check.
class FileCheckDayStore implements CheckDayStore {
  FileCheckDayStore(this._file);

  final JsonFile _file;

  @override
  Future<DateTime?> lastRun() async {
    final checked = (await _file.read())?['checked'];
    return checked is String ? DateTime.tryParse(checked) : null;
  }

  @override
  Future<void> recordRun(DateTime day) => _file.write({
    'checked':
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}',
  });
}

class MemoryCheckDayStore implements CheckDayStore {
  DateTime? _day;

  @override
  Future<DateTime?> lastRun() async => _day;

  @override
  Future<void> recordRun(DateTime day) async => _day = day;
}

/// Whether a check whose last run was [last] is due on [now]'s day: never
/// run, or last run on an earlier day.
bool checkDueOn(DateTime? last, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return last == null || last.isBefore(today);
}
