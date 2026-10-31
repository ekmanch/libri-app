import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/widgets/labels.dart';

void main() {
  group('status words per type', () {
    test('In progress reads Reading, Watching or Playing by type', () {
      const inProgress = EntryStatus.inProgress;
      expect(inProgress.labelFor(MediaType.books), 'Reading');
      expect(inProgress.labelFor(MediaType.shows), 'Watching');
      expect(inProgress.labelFor(MediaType.anime), 'Watching');
      expect(inProgress.labelFor(seasonsType), 'Watching');
      expect(inProgress.labelFor(MediaType.games), 'Playing');
    });

    test('mixed types keep In progress', () {
      expect(EntryStatus.inProgress.labelFor(null), 'In progress');
      expect(EntryStatus.inProgress.lowerLabelFor(null), 'in progress');
    });

    test('the other statuses read the same for every type', () {
      for (final type in [null, ...MediaType.values]) {
        expect(EntryStatus.want.labelFor(type), 'Want');
        expect(EntryStatus.done.labelFor(type), 'Done');
        expect(EntryStatus.dnf.labelFor(type), 'DNF');
        expect(EntryStatus.dnf.lowerLabelFor(type), 'DNF');
      }
    });

    test('mid-sentence words are lowercase', () {
      expect(EntryStatus.inProgress.lowerLabelFor(MediaType.books), 'reading');
      expect(EntryStatus.want.lowerLabelFor(MediaType.games), 'want');
    });
  });
}
