import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/languages.dart';
import 'package:library_app/data/models/media_type.dart';

void main() {
  test('two- and three-letter codes, with a region, name the tag', () {
    expect(languageTag('ja'), 'japanese');
    expect(languageTag('jpn'), 'japanese');
    expect(languageTag('ja-JP'), 'japanese');
    expect(languageTag('pt_BR'), 'portuguese');
    expect(languageTag('SV'), 'swedish');
    expect(languageTag('nb'), 'norwegian');
    expect(languageTag('nno'), 'norwegian');
    expect(languageTag('ger'), 'german');
    expect(languageTag('deu'), 'german');
    expect(languageTag('en-US'), 'english');
  });

  test('an unknown, empty or missing code names nothing', () {
    expect(languageTag(null), isNull);
    expect(languageTag(''), isNull);
    expect(languageTag('xx'), isNull);
    expect(languageTag('klingon'), isNull);
  });

  test('English is never suggested, nor Japanese for an anime', () {
    expect(languageSuggestion(MediaType.movies, 'en'), isNull);
    expect(languageSuggestion(MediaType.books, 'eng'), isNull);
    expect(languageSuggestion(MediaType.anime, 'ja'), isNull);
    expect(languageSuggestion(MediaType.anime, 'ko'), 'korean');
    expect(languageSuggestion(MediaType.movies, 'ja'), 'japanese');
    expect(languageSuggestion(MediaType.games, 'ja-JP'), 'japanese');
    expect(languageSuggestion(MediaType.books, null), isNull);
  });

  test('AniList\'s country of origin says the language for JP, KR and CN', () {
    expect(languageOfCountry('JP'), 'ja');
    expect(languageOfCountry('kr'), 'ko');
    expect(languageOfCountry('CN'), 'zh');
    expect(languageOfCountry('TW'), 'zh');
    expect(languageOfCountry('US'), isNull);
    expect(languageOfCountry(null), isNull);
  });
}
