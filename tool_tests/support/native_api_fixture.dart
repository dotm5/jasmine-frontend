// Synthetic HTTP data, never a capture of a real account or content service.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jasmine/backend/backend_client.dart';
import 'package:jasmine/backend/backend_transport.dart';
import 'package:jasmine/basic/methods.dart';

const fixturePng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

Map<String, dynamic> comicFixture([int id = 101]) => {
  'id': '$id',
  'author': 'Fixture author',
  'description': null,
  'name': 'Fixture $id',
  'image': '',
  'category': {'id': '1', 'title': 'Fixture'},
  'category_sub': {'id': null, 'title': null},
};

Map<String, dynamic> albumFixture(int id) => {
  'id': '$id',
  'name': 'Fixture $id',
  'author': ['Fixture author'],
  'images': ['00001.png'],
  'description': null,
  'total_views': '1',
  'likes': '0',
  'series': [
    {'id': '$id', 'name': 'Chapter', 'sort': '1'},
  ],
  'series_id': '0',
  'comment_total': '1',
  'tags': ['fixture'],
  'works': [],
  'related_list': [],
  'liked': false,
  'is_favorite': true,
};

Map<String, dynamic> userFixture() => {
  'uid': '42',
  'username': 'fixture-user',
  'email': '',
  'emailverified': '0',
  'photo': '',
  'fname': '',
  'gender': '',
  'message': null,
  'coin': '0',
  'album_favorites': 1,
  's': '',
  'favorite_list': [],
  'level_name': 'Fixture',
  'level': 1,
  'nextLevelExp': 10,
  'exp': '0',
  'expPercent': 0.0,
  'badges': [],
  'album_favorites_max': 100,
};

Map<String, dynamic> commentFixture() => {
  'AID': '101',
  'CID': '7',
  'UID': '42',
  'username': 'fixture-user',
  'nickname': 'Fixture',
  'likes': '0',
  'gender': '',
  'update_at': '2026-08-28',
  'addtime': '2026-08-28',
  'parent_CID': '0',
  'name': 'Fixture 101',
  'content': 'Fixture comment',
  'photo': '',
  'spoiler': '0',
  'replys': [],
  'expinfo': {
    'level_name': 'Fixture',
    'level': 1,
    'nextLevelExp': 10,
    'exp': '0',
    'expPercent': 0.0,
    'uid': '42',
    'badges': [],
  },
};

class HttpCall {
  HttpCall(this.method, this.uri, this.body, this.cookie);
  final String method;
  final Uri uri;
  final String body;
  final String? cookie;
  Map<String, String> get form => Uri.splitQueryString(body);
}

class ApiFixture {
  ApiFixture._(this.server);
  final HttpServer server;
  final calls = <HttpCall>[];
  final unexpected = <String>[];
  String? davDocument;
  int davGetStatus = 200;
  bool failFavoriteAction = false;
  bool malformedFavorite = false;
  String get origin => 'http://127.0.0.1:${server.port}';

  static Future<ApiFixture> start() async {
    final result = ApiFixture._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    result.server.listen(result._respond);
    return result;
  }

  Future<void> _respond(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    calls.add(
      HttpCall(
        request.method,
        request.uri,
        body,
        request.headers.value(HttpHeaders.cookieHeader),
      ),
    );
    final path = request.uri.path;
    if (path.startsWith('/media/')) {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(base64Decode(fixturePng));
      await request.response.close();
      return;
    }
    if (path == '/raw') {
      request.response.write('fixture text');
      await request.response.close();
      return;
    }
    if (path == '/dav') {
      if (request.method == 'GET') {
        request.response.statusCode =
            davGetStatus != 200
                ? davGetStatus
                : (davDocument == null ? 404 : 200);
        if (request.response.statusCode == 200) {
          request.response.write(davDocument);
        }
      } else if (request.method == 'PUT') {
        davDocument = body;
        request.response.statusCode = 201;
      } else {
        unexpected.add('${request.method} $path');
        request.response.statusCode = 405;
      }
      await request.response.close();
      return;
    }
    dynamic data;
    switch (path) {
      case '/':
        data = <String, dynamic>{};
      case '/login':
        request.response.headers.add('set-cookie', 'session=fixture==; Path=/');
        data = userFixture();
      case '/categories':
        data = {
          'categories': [
            {
              'id': '1',
              'name': 'Fixture',
              'slug': 'fixture',
              'total_albums': '1',
              'type': null,
            },
          ],
          'blocks': [
            {
              'title': 'Fixture',
              'content': ['fixture'],
            },
          ],
        };
      case '/categories/filter':
      case '/search':
        data = {
          'search_query': request.uri.queryParameters['search_query'] ?? '',
          'total': '1',
          'content': [comicFixture()],
          'redirect_aid': null,
        };
      case '/album':
        data = albumFixture(int.parse(request.uri.queryParameters['id']!));
      case '/chapter':
        final id = request.uri.queryParameters['id']!;
        data = {
          'id': id,
          'series': [
            {'id': id, 'name': 'Chapter', 'sort': '1'},
          ],
          'tags': 'fixture',
          'name': 'Chapter',
          'images': ['00001.png'],
          'series_id': '0',
          'is_favorite': true,
          'liked': false,
        };
      case '/favorite':
        if (request.method == 'POST') {
          data = {
            'status': failFavoriteAction ? 'fail' : 'ok',
            'msg': failFavoriteAction ? 'fixture denied' : 'updated',
            'type': 'add',
          };
        } else {
          data =
              malformedFavorite
                  ? {'total': 'bad'}
                  : {
                    'total': '1',
                    'count': '1',
                    'list': [comicFixture()],
                    'folder_list': [
                      {'FID': '17', 'UID': '42', 'name': 'Fixture folder'},
                    ],
                  };
        }
      case '/favorite_folder':
        data = {
          'status': failFavoriteAction ? 'fail' : 'ok',
          'msg': failFavoriteAction ? 'fixture denied' : 'updated',
        };
      case '/week':
        data = {
          'categories': [
            {'id': 1, 'time': '2026-08-28', 'title': 'Fixture week'},
          ],
          'type': [
            {'id': 2, 'title': 'Fixture type'},
          ],
        };
      case '/week/filter':
        data = {
          'total': '1',
          'list': [comicFixture()],
        };
      case '/forum':
        data = {
          'total': '1',
          'list': [commentFixture()],
        };
      case '/comment':
        data = {
          'status': 'ok',
          'msg': 'updated',
          'aid': 101,
          'cid': 7,
          'spoiler': '0',
        };
      case '/daily':
        data = {
          'daily_id': 73,
          'record': [
            [
              {'date': 'D1', 'signed': false, 'bonus': false},
            ],
          ],
        };
      case '/daily_chk':
        data = {'msg': 'fixture signed'};
      case '/games':
        final game = {
          'gid': '1',
          'title': 'Fixture',
          'description': '',
          'tags': '',
          'link': '',
          'link_title': '',
          'photo': '',
          'type': ['fixture'],
          'categories': {'name': 'Fixture', 'slug': 'fixture'},
          'update_at': '1',
          'total_clicks': '0',
          'order_rank': '1',
          'status': '1',
          'show_lang': ['en'],
        };
        data = {
          'games': [game],
          'games_total': '1',
          'categories': [
            {'name': 'Fixture', 'slug': 'fixture'},
          ],
          'hot_games': [],
        };
      default:
        unexpected.add('${request.method} $path');
        request.response.statusCode = 404;
        data = <String, dynamic>{};
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'code': 200, 'data': data}));
    await request.response.close();
  }

  Future<void> close() => server.close(force: true);
}

class NativeTransport implements BackendTransport {
  NativeTransport._(this.process, this.directory, this.outcomes);
  final Process process;
  final Directory directory;
  final Map<String, Set<String>> outcomes;
  final pending = <Completer<String>>[];
  final ready = Completer<void>();
  final stderr = StringBuffer();
  late StreamSubscription<String> output;
  late StreamSubscription<String> errors;

  static Future<NativeTransport> start(
    String binary,
    Map<String, Set<String>> outcomes,
  ) async {
    final root = Directory('${Directory.current.path}/.tmp/api-audit-20260828')
      ..createSync(recursive: true);
    final directory = root.createTempSync('runtime-');
    final process = await Process.start(binary, ['${directory.path}/data']);
    final result = NativeTransport._(process, directory, outcomes);
    result.output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line == 'BRIDGE_READY' && !result.ready.isCompleted) {
            result.ready.complete();
          }
          if (line.startsWith('BRIDGE_REPLY ') && result.pending.isNotEmpty) {
            result.pending.removeAt(0).complete(line.substring(13));
          }
        });
    result.errors = process.stderr
        .transform(utf8.decoder)
        .listen(result.stderr.write);
    process.exitCode.then((code) {
      final error = StateError(
        'Native fixture exited ($code): ${result.stderr}',
      );
      if (!result.ready.isCompleted) result.ready.completeError(error);
      for (final reply in result.pending) {
        if (!reply.isCompleted) reply.completeError(error);
      }
      result.pending.clear();
    });
    await result.ready.future.timeout(const Duration(seconds: 15));
    return result;
  }

  @override
  Future<String> send(String request) async {
    final method = jsonDecode(request)['method'] as String;
    final response = Completer<String>();
    pending.add(response);
    process.stdin.writeln(request);
    final text = await response.future.timeout(const Duration(seconds: 15));
    final envelope = jsonDecode(text) as Map<String, dynamic>;
    outcomes
        .putIfAbsent(method, () => {})
        .add(envelope['error_message'] == '' ? 'success' : 'error');
    return text;
  }

  Methods get api => Methods(backend: BackendClient(this));

  Future<void> close() async {
    await process.stdin.close();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
    }
    await output.cancel();
    await errors.cancel();
  }
}
