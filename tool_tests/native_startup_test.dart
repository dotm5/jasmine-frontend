import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/configs/login.dart';
import 'package:jasmine/configs/network_api_host.dart';
import 'package:jasmine/configs/network_cdn_host.dart';
import 'package:jasmine/screens/first_login_screen.dart';
import 'package:jasmine/screens/init_screen.dart';

// Host-only cross-language integration: real Rust + SQLite + Dart serializers.
// JNI, Android permissions and real network services still need device tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final binary = Platform.environment['JASMINE_TEST_BRIDGE_BINARY'];

  testWidgets(
    'fresh native backend initializes the complete Flutter config stack',
    (tester) async {
      final root = Directory('${Directory.current.path}/.tmp');
      root.createSync(recursive: true);
      final fixture = root.createTempSync('native-startup-');
      late Process process;
      late StreamSubscription<String> output;
      late StreamSubscription<String> errors;
      final pending = <Completer<String>>[];
      final invoked = <String>[];
      final stderr = StringBuffer();
      // Keep process I/O in the real async zone; the widget pump below waits for
      // real replies rather than advancing a fictitious process startup timer.
      await tester.runAsync(() async {
        process = await Process.start(binary!, ['${fixture.path}/data']);
        output = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (line.startsWith('BRIDGE_REPLY ')) {
                if (pending.isEmpty) {
                  throw StateError('Unexpected backend reply');
                }
                pending
                    .removeAt(0)
                    .complete(line.substring('BRIDGE_REPLY '.length));
              }
            });
        errors = process.stderr.transform(utf8.decoder).listen(stderr.write);
        process.exitCode.then((code) {
          final error = StateError('Fixture exited ($code): $stderr');
          for (final reply in pending) {
            if (!reply.isCompleted) reply.completeError(error);
          }
          pending.clear();
        });
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        // The fixture owns only the fresh synthetic directory above. Do not wait
        // for an IOSink close on WidgetTester's stopped fake clock at teardown.
        process.kill();
        unawaited(output.cancel());
        unawaited(errors.cancel());
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'invoke');
            final request = call.arguments as String;
            invoked.add(jsonDecode(request)['method'] as String);
            final response = Completer<String>();
            pending.add(response);
            process.stdin.writeln(request);
            return response.future;
          });
      await tester.pumpWidget(const MaterialApp(home: InitScreen()));
      for (var i = 0; i < 160; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(FirstLoginScreen).evaluate().isNotEmpty ||
            find.text('初始化失败').evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(find.text('初始化失败'), findsNothing, reason: stderr.toString());
      expect(find.byType(FirstLoginScreen), findsOneWidget);
      expect(loginStatus, LoginStatus.notSet);
      // Startup must not silently rewrite an explicit HTTP custom origin to
      // HTTPS while merging the API/CDN candidate lists.
      expect(currentApiHostName, 'http://127.0.0.1:1');
      expect(currentCdnHostName, 'http://127.0.0.1:1');
      expect(
        invoked,
        containsAll([
          'init_dart',
          'init_dart2',
          'pro_info_all',
          'pre_login',
          'load_property',
        ]),
      );
      expect(
        invoked.any(
          (method) => [
            'daily',
            'login',
            'reload_pro',
            'input_cd_key',
            'check_pat',
          ].contains(method),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
    skip: binary == null,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
