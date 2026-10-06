import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/configs/auto_clean.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cache settings persist retention and capacity independently', (
    tester,
  ) async {
    final saved = <String, String>{
      'auto_clean': '604800',
      'cache_max_bytes': '2147483648',
    };
    const channel = MethodChannel('methods');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      var result = '';
      if (request['method'] == 'load_property') {
        result = saved[request['params']] ?? '';
      }
      if (request['method'] == 'save_property') {
        final params =
            jsonDecode(request['params'] as String) as Map<String, dynamic>;
        saved[params['k'] as String] = params['v'] as String;
      }
      return jsonEncode({'error_message': '', 'response_data': result});
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await initAutoClean();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () => chooseAutoClean(context),
                  child: const Text('设置'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片缓存容量上限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('512 MB'));
    await tester.pumpAndSettle();
    expect(saved['cache_max_bytes'], '536870912');
    expect(saved['auto_clean'], '604800');
    await tester.tap(find.text('图片缓存保留时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一天'));
    await tester.pumpAndSettle();
    expect(saved['auto_clean'], '86400');
    expect(saved['cache_max_bytes'], '536870912');
    expect(tester.takeException(), isNull);
  });
}
