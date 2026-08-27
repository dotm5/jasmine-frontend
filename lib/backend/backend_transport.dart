/// Exchanges one JSON request/reply. No Flutter, JNI or business-model dependency.
abstract interface class BackendTransport {
  Future<String> send(String request);
}
