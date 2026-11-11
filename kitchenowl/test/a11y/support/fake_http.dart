/// An `HttpOverrides` that answers the app's requests from a [FakeServer],
/// without a socket.
///
/// The app builds its HTTP client itself (`IOClient(HttpClient())` in a
/// private constructor of `ApiService`), so the lowest seam, `dart:io`'s
/// `HttpClient`, is the only one that can be replaced without editing `lib/`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'fake_server.dart';

class FakeHttpOverrides extends HttpOverrides {
  FakeHttpOverrides(this.server);

  final FakeServer server;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(server);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._server);

  final FakeServer _server;

  @override
  String? userAgent;

  @override
  bool autoUncompress = true;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Duration? connectionTimeout;

  @override
  int? maxConnectionsPerHost;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (!_server.reachable) {
      await Future<void>.delayed(_server.latency);
      throw SocketException(
        'Connection refused',
        address: InternetAddress.loopbackIPv4,
        port: url.port,
      );
    }
    return _FakeRequest(_server, method, url);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'a11y harness: HttpClient.${invocation.memberName}');
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._server, this.method, this.uri);

  final FakeServer _server;

  @override
  final String method;

  @override
  final Uri uri;

  final BytesBuilder _body = BytesBuilder();

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  bool bufferOutput = true;

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => _body.add(data);

  @override
  void write(Object? object) => _body.add(utf8.encode('$object'));

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(_body.add);

  @override
  Future<void> flush() async {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async {
    await Future<void>.delayed(_server.latency);
    final reply = _server.handle(
      method,
      uri,
      authorization: headers.value(HttpHeaders.authorizationHeader),
      body: utf8.decode(_body.takeBytes(), allowMalformed: true),
    );
    return _FakeResponse(reply);
  }

  @override
  Future<HttpClientResponse> get done => Completer<HttpClientResponse>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'a11y harness: HttpClientRequest.${invocation.memberName}');
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this._reply) : _bytes = utf8.encode(_reply.body);

  final Reply _reply;
  final List<int> _bytes;

  @override
  int get statusCode => _reply.status;

  @override
  String get reasonPhrase => _reply.status == 200 ? 'OK' : 'Error';

  @override
  int get contentLength => _bytes.length;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  bool get persistentConnection => true;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  late final HttpHeaders headers = _FakeHeaders()
    ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(_bytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'a11y harness: HttpClientResponse.${invocation.memberName}');
}

class _FakeHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = ['$value'];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      (_values[name.toLowerCase()] ??= []).add('$value');

  @override
  String? value(String name) => _values[name.toLowerCase()]?.join(', ');

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(action);

  @override
  ContentType? get contentType {
    final value = this.value(HttpHeaders.contentTypeHeader);
    return value == null ? null : ContentType.parse(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'a11y harness: HttpHeaders.${invocation.memberName}');
}
