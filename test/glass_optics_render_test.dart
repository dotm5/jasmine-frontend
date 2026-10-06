import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('glass optics keep local geometry at different pixel densities', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/hot_glass.frag',
      );
      for (final ratio in [1, 3]) {
        final shader = program.fragmentShader();
        final values = <double>[
          300,
          80,
          0,
          .5,
          .5,
          0,
          28,
          1.25,
          0,
          0,
          -.78,
          -.62,
        ];
        for (var i = 0; i < values.length; i++) {
          shader.setFloat(i, values[i]);
        }
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..scale(ratio.toDouble());
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 300, 80),
          ui.Paint()..shader = shader,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(300 * ratio, 80 * ratio);
        final pixels =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        int alpha(int x, int y) =>
            pixels.getUint8(((y * ratio) * 300 * ratio + x * ratio) * 4 + 3);
        expect(
          alpha(150, 40),
          lessThan(4),
          reason: 'No painted reflection stripe through the centre',
        );
        expect(
          alpha(150, 2),
          greaterThan(alpha(150, 77)),
          reason: 'Highlight faces the shared upper light',
        );
        for (var i = 0; i < pixels.lengthInBytes; i += 4) {
          final a = pixels.getUint8(i + 3);
          expect(pixels.getUint8(i), lessThanOrEqualTo(a));
          expect(pixels.getUint8(i + 1), lessThanOrEqualTo(a));
          expect(pixels.getUint8(i + 2), lessThanOrEqualTo(a));
        }
        final dir = Directory('.tmp/glass-audit')..createSync(recursive: true);
        File('${dir.path}/optics-${ratio}x.png').writeAsBytesSync(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
        image.dispose();
        picture.dispose();
        shader.dispose();
      }
    });
  });
}
