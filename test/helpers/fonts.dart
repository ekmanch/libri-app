import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the bundled fonts, so a test can measure real text widths
/// instead of the test environment's square placeholder glyphs.
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File(file).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Figtree', [
    'assets/fonts/figtree/Figtree-Regular.ttf',
    'assets/fonts/figtree/Figtree-Italic.ttf',
    'assets/fonts/figtree/Figtree-Medium.ttf',
    'assets/fonts/figtree/Figtree-SemiBold.ttf',
    'assets/fonts/figtree/Figtree-Bold.ttf',
    'assets/fonts/figtree/Figtree-ExtraBold.ttf',
  ]);
}
