import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/user_agent.dart';

void main() {
  test('the User-Agent names the version and links back', () {
    expect(
      userAgentFor('1.2.0'),
      'Libri/1.2.0 (https://github.com/ekmanch/library-app)',
    );
    expect(lookupUserAgent, startsWith('Libri ('));
  });
}
