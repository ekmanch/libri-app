import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/text_clean.dart';

void main() {
  test('stripHtml drops tags, keeps breaks and decodes entities', () {
    expect(
      stripHtml(
        '<p>A biker gang &amp; a <i>secret</i> project.<br>Neo-Tokyo.</p>'
        '<p>Based on the manga &quot;Akira&quot;&#39;s first arc.</p>',
      ),
      'A biker gang & a secret project.\nNeo-Tokyo.\n\n'
      'Based on the manga "Akira"\'s first arc.',
    );
    expect(stripHtml('  plain   text  '), 'plain text');
    expect(stripHtml('a<br/><br/><br/>b'), 'a\n\nb');
    expect(stripHtml('&#233;t&eacute;'), 'ét&eacute;');
    // Apple Books writes a hex entity for its non-breaking spaces.
    expect(
      stripHtml('<i>Shogun</i>&#xa0;and <i>King Rat</i>'),
      'Shogun and King Rat',
    );
  });

  test('sameTitle ignores case, punctuation, diacritics and a leading The', () {
    expect(sameTitle("Salem's Lot", 'Salems lot'), isTrue);
    expect(sameTitle('The Mummy', 'Mummy'), isTrue);
    expect(sameTitle('Blade Runner 2049', 'Blade Runner'), isFalse);
    expect(sameTitle('WALL·E', 'Wall-E'), isTrue);
    expect(sameTitle('Dune', 'Dune: Part Two'), isFalse);
  });
}
