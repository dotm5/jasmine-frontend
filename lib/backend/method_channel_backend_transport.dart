import 'package:flutter/services.dart';

import 'backend_transport.dart';

/// Flutter platform adapter; Android forwards this channel to the JNI library.
class MethodChannelBackendTransport implements BackendTransport {
  const MethodChannelBackendTransport({
    this.channel = const MethodChannel('methods'),
  });

  final MethodChannel channel;

  @override
  Future<String> send(String request) async {
    final response = await channel.invokeMethod<String>('invoke', request);
    if (response == null) {
      throw StateError('Empty response from native backend');
    }
    return response;
  }
}
