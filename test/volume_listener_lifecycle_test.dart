import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/screens/comic_reader_screen.dart';

void main() {
  testWidgets(
    'volume subscriptions balance across nested readers and extra releases',
    (tester) async {
      final calls = <String>[];
      const channel = MethodChannel('volume_button');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      addVolumeListen();
      addVolumeListen();
      await tester.pump();
      expect(calls, ['listen']);
      delVolumeListen();
      await tester.pump();
      expect(calls, ['listen']);
      delVolumeListen();
      await tester.pump();
      expect(calls, ['listen', 'cancel']);
      delVolumeListen();
      addVolumeListen();
      await tester.pump();
      expect(calls, ['listen', 'cancel', 'listen']);
      delVolumeListen();
      await tester.pump();
      expect(calls, ['listen', 'cancel', 'listen', 'cancel']);
    },
  );
}
