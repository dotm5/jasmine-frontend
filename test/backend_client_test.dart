import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/backend/backend_client.dart';
import 'package:jasmine/backend/backend_transport.dart';
import 'package:jasmine/backend/method_channel_backend_transport.dart';
import 'package:jasmine/basic/methods.dart';

class RecordingTransport implements BackendTransport {
  final requests = <Map<String, dynamic>>[];
  String reply = jsonEncode({'error_message': '', 'response_data': ''});

  @override
  Future<String> send(String request) async {
    requests.add(jsonDecode(request) as Map<String, dynamic>);
    return reply;
  }
}

void main() {
  test(
    'v1 preserves string, object, list and numeric parameter encoding',
    () async {
      final transport = RecordingTransport();
      final client = BackendClient(transport);
      for (final params in <dynamic>[
        '收藏 & +? 📚',
        {'k': 'key', 'v': 'value'},
        ['17', 'folder'],
        42,
      ]) {
        await client.invoke('fixture', params);
        expect(transport.requests.last, {
          'method': 'fixture',
          'params': params is String ? params : jsonEncode(params),
        });
      }
    },
  );

  test('client returns the undecoded response string', () async {
    final transport =
        RecordingTransport()
          ..reply = jsonEncode({
            'error_message': '',
            'response_data': '{"id":42}',
          });
    expect(await BackendClient(transport).invoke('fixture', ''), '{"id":42}');
  });

  test('backend errors retain their message', () async {
    final transport =
        RecordingTransport()
          ..reply = jsonEncode({
            'error_message': 'API action failed',
            'response_data': '',
          });
    await expectLater(
      BackendClient(transport).invoke('fixture', ''),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'API action failed',
        ),
      ),
    );
  });

  test('malformed envelopes fail at the client boundary', () async {
    final transport = RecordingTransport();
    for (final reply in [
      'not json',
      'null',
      '[]',
      '{}',
      '{"error_message":"","response_data":42}',
    ]) {
      transport.reply = reply;
      await expectLater(
        BackendClient(transport).invoke('fixture', ''),
        throwsFormatException,
      );
    }
  });

  test(
    'typed frontend methods accept a backend without a platform channel',
    () async {
      final transport =
          RecordingTransport()
            ..reply = jsonEncode({
              'error_message': '',
              'response_data': '打卡成功',
            });
      final api = Methods(backend: BackendClient(transport));
      expect(await api.daily(42), '打卡成功');
      expect(transport.requests.single, {'method': 'daily', 'params': '42'});
      await api.renameFavoriteFolder(17, '收藏 & +? 📚');
      expect(jsonDecode(transport.requests.last['params']), [
        '17',
        '收藏 & +? 📚',
      ]);
    },
  );

  test('platform adapter reports a missing reply', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('backend-null-fixture');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(
      const MethodChannelBackendTransport(channel: channel).send('{}'),
      throwsStateError,
    );
  });
}
