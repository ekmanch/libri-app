import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:library_app/data/covers/cover_picture.dart';
import 'package:library_app/data/github/git_blob.dart';

/// A PNG of [width] × [height]: red on the left half, blue on the right,
/// see-through where [clear].
Uint8List png(int width, int height, {bool clear = false}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (final pixel in image) {
    if (pixel.x < width ~/ 2) {
      pixel.setRgba(255, 0, 0, clear ? 0 : 255);
    } else {
      pixel.setRgba(0, 0, 255, 255);
    }
  }
  return img.encodePng(image);
}

void main() {
  const pictures = EngineCoverPictures();

  testWidgets('an upload is scaled to 1000 px on its longer side, as JPEG', (
    tester,
  ) async {
    await tester.runAsync(() async {
      expect(await pictures.sizeOf(png(1600, 2400)), (1600, 2400));
      final prepared = await pictures.prepare(png(1600, 2400));
      expect((prepared.width, prepared.height), (667, 1000));
      expect(prepared.sha, gitBlobSha(prepared.bytes));
      // A JPEG, of that size.
      expect(prepared.bytes.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
      final decoded = img.decodeJpg(prepared.bytes)!;
      expect((decoded.width, decoded.height), (667, 1000));
      // Never scaled up.
      final small = await pictures.prepare(png(200, 300));
      expect((small.width, small.height), (200, 300));
    });
  });

  testWidgets('a see-through image is put on white', (tester) async {
    await tester.runAsync(() async {
      final prepared = await pictures.prepare(png(200, 300, clear: true));
      final decoded = img.decodeJpg(prepared.bytes)!;
      final left = decoded.getPixel(20, 150);
      expect(left.r, greaterThan(240));
      expect(left.g, greaterThan(240));
      expect(left.b, greaterThan(240));
      final right = decoded.getPixel(180, 150);
      expect(right.b, greaterThan(200));
      expect(right.r, lessThan(60));
    });
  });

  testWidgets('Fit your cover keeps the frame where it was left', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // A wide image, red left and blue right: the frame at the left end
      // is all red, at the right end all blue.
      final wide = png(1920, 1080);
      final left = await pictures.fit(wide, at: 0, square: false);
      expect((left.width, left.height), (720, 1080));
      final leftPixel = img.decodeJpg(left.bytes)!.getPixel(360, 540);
      expect(leftPixel.r, greaterThan(200));
      expect(leftPixel.b, lessThan(60));
      final right = await pictures.fit(wide, at: 1, square: false);
      final rightPixel = img.decodeJpg(right.bytes)!.getPixel(360, 540);
      expect(rightPixel.b, greaterThan(200));
      expect(rightPixel.r, lessThan(60));
      // A large one is saved at 1000 × 1500; music at 1000 × 1000.
      final large = await pictures.fit(png(3000, 2000), at: 0.5, square: false);
      expect((large.width, large.height), (1000, 1500));
      final square = await pictures.fit(png(3000, 2000), at: 0.5, square: true);
      expect((square.width, square.height), (1000, 1000));
    });
  });

  testWidgets('a file that is not an image says so', (tester) async {
    await tester.runAsync(() async {
      await expectLater(
        pictures.sizeOf(Uint8List.fromList('not an image'.codeUnits)),
        throwsA(isA<CoverPictureException>()),
      );
      await expectLater(
        pictures.prepare(Uint8List(0)),
        throwsA(isA<CoverPictureException>()),
      );
    });
  });
}
