import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/features/entry/track_paste.dart';

void main() {
  List<(String, String)> parsed(String text) => [
    for (final t in parseTrackList(text)) (t.title, t.length),
  ];

  test('a pasted list loses its numbers and keeps its lengths', () {
    expect(
      parsed(
        "1. Hometown Glory 4:31\n01 - I'll Be Waiting (4:07)\n"
        "3) Don't You Remember\n\n",
      ),
      [
        ('Hometown Glory', '4:31'),
        ("I'll Be Waiting", '4:07'),
        ("Don't You Remember", ''),
      ],
    );
    expect(
      parsed('4 – Turning Tables – 4:51\n5\tSet Fire to the Rain [1:04:20]'),
      [('Turning Tables', '4:51'), ('Set Fire to the Rain', '1:04:20')],
    );
  });

  test('a title that starts with a number keeps it', () {
    expect(parsed('99 Problems'), [('99 Problems', '')]);
    expect(parsed('99 Problems\nEncore 4:11'), [
      ('99 Problems', ''),
      ('Encore', '4:11'),
    ]);
    // Every line numbered with a bare number: the numbers go.
    expect(parsed('1 Angel 6:18\n2 Risingson\n3 1979'), [
      ('Angel', '6:18'),
      ('Risingson', ''),
      ('1979', ''),
    ]);
    // A year, a number alone and a time in a title are not lengths or
    // numbers.
    expect(parsed('1979'), [('1979', '')]);
    expect(parsed('2. 7'), [('7', '')]);
    expect(parsed('Live at 9:30 Club'), [('Live at 9:30 Club', '')]);
    expect(parsed('Track(4:31'), [('Track(4:31', '')]);
  });
}
