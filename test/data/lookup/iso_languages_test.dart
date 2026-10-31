import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/iso_languages.dart';

void main() {
  test('every ISO 639-1 language, once, A to Z by English name', () {
    expect(isoLanguages, hasLength(184));
    final codes = {for (final l in isoLanguages) l.code};
    expect(codes, hasLength(isoLanguages.length));
    expect(codes.every((c) => c.length == 2), isTrue);
    final codes3 = [for (final l in isoLanguages) ...l.codes3];
    expect(codes3.toSet(), hasLength(codes3.length));
    expect(codes3.every((c) => c.length == 3), isTrue);
    final names = [for (final l in isoLanguages) l.name];
    expect(names, [...names]..sort());
  });

  test('looks up by two-letter code, three-letter code or locale', () {
    expect(isoLanguage('sv')!.name, 'Swedish');
    expect(isoLanguage('swe')!.code, 'sv');
    expect(isoLanguage('sv-SE')!.code, 'sv');
    expect(isoLanguage('sv_SE')!.code, 'sv');
    expect(isoLanguage('GER')!.code, 'de');
    expect(isoLanguage('deu')!.code, 'de');
    expect(isoLanguage('xx'), isNull);
    expect(isoLanguage(null), isNull);
    expect(isoLanguageCode('jpn'), 'ja');
    expect(isoLanguageCode('tlh'), isNull);
  });

  test('labels and names', () {
    expect(isoLanguage('tr')!.label, 'Turkish · Türkçe');
    expect(isoLanguage('en')!.label, 'English');
    expect(isoLanguage('tr')!.matches('türk'), isTrue);
    expect(isoLanguage('tr')!.matches('TURK'), isTrue);
    expect(isoLanguage('tr')!.matches('sv'), isFalse);
    expect(isoLanguageNames(['tr', 'en', 'xx']), 'English, Turkish, xx');
  });

  test('the default languages read: the phone\'s plus English, sorted', () {
    expect(defaultReadingLanguages(['sv-SE', 'en-US', 'sv']), ['en', 'sv']);
    expect(defaultReadingLanguages(['tr']), ['en', 'tr']);
    expect(defaultReadingLanguages([]), ['en']);
    expect(defaultReadingLanguages(['xx', 'ja-JP']), ['en', 'ja']);
  });
}
