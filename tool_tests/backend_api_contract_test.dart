// Real Dart serializers -> native dispatcher -> loopback HTTP / fresh SQLite.
// All accounts, images and remote documents below are synthetic fixtures.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/methods.dart';

import 'support/native_api_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final binary = Platform.environment['JASMINE_TEST_BRIDGE_BINARY'];
  final outcomes = <String, Set<String>>{};
  final retired = {
    'bind_pat',
    'check_pat',
    'input_cd_key',
    'reload_pat_account',
    'reload_pro',
  };
  group('native API contract', () {
    late ApiFixture server;
    late NativeTransport transport;
    late Methods api;

    setUp(() async {
      server = await ApiFixture.start();
      addTearDown(server.close);
      transport = await NativeTransport.start(binary!, outcomes);
      addTearDown(transport.close);
      api = transport.api;
      await api.saveApiHost(server.origin);
      await api.saveCdnHost(server.origin);
      addTearDown(() => expect(server.unexpected, isEmpty));
    });

    test('configuration and real local state round-trip', () async {
      await api.init();
      await api.init2();
      await api.backend.invoke('init', '');
      expect(await api.backend.invoke('test', ''), '');
      await api.backend.invoke('set_pro_server_name', 'fixture-local');
      expect(
        await api.backend.invoke('get_pro_server_name', ''),
        'fixture-local',
      );
      final config = await api.appConfig();
      expect(config['apiHosts'], isNotEmpty);
      expect(config['cdnHosts'], isNotEmpty);
      expect(config['membershipService'], isFalse);
      expect(await api.configLinks(), isA<Map<String, String>>());
      expect(await api.loadApiHost(), server.origin);
      expect(await api.loadCdnHost(), server.origin);
      await api.saveProperty('fixture-property', 'value & +? 📚');
      expect(await api.loadProperty('fixture-property'), 'value & +? 📚');
      await api.deleteProperty('fixture-property');
      expect(await api.loadProperty('fixture-property'), '');
      await api.set_download_thread(3);
      expect(await api.load_download_thread(), 3);
      await api.setDownloadAndExportTo(transport.directory.path);
      expect(await api.getDownloadAndExportTo(), transport.directory.path);
      await api.setDownloadAndExportTo('');
      await api.setProxy('');
      expect(await api.getProxy(), '');
      expect(await api.getHomeDir(), isNotEmpty);
      expect((await api.preLogin()).preSet, isFalse);
      expect(await api.loadUsername(), '');
      expect(await api.loadPassword(), '');
      expect(await api.loadLastLoginUsername(), '');
      expect((await api.isPro()).isPro, isFalse);
      expect((await api.proInfoAll()).proInfoAf.isPro, isFalse);
      await api.clearPat();
    });

    test(
      'category, ordinary rankings, search and games decode nonempty DTOs',
      () async {
        await api.login('fixture-user', 'fixture-password');
        expect((await api.categories()).categories, hasLength(1));
        for (final order in sorts) {
          final comics = await api.comics('fixture', order, 1);
          expect(comics.content.single.id, 101);
          final request = server.calls.lastWhere(
            (call) => call.uri.path == '/categories/filter',
          );
          expect(request.uri.queryParameters['o'], order.value);
        }
        final search = await api.comicSearch('fixture & +?', sortByNew, 2);
        expect(search.content.single.id, 101);
        expect(
          server.calls.last.uri.queryParameters['search_query'],
          'fixture & +?',
        );
        expect(server.calls.last.uri.queryParameters['page'], '2');
        expect(
          (await api.lastSearchHistories(10)).single.searchQuery,
          'fixture & +?',
        );
        await api.clearASearchLog('fixture & +?');
        expect(await api.lastSearchHistories(10), isEmpty);
        await api.clearAllSearchLog();
        final games = await api.games(1);
        expect(games.games, hasLength(1));
        expect(games.gamesTotal, '1');
        expect(games.categories.single.slug, 'fixture');
      },
    );

    test(
      'every advertised API index resolves and custom selection reaches its origin',
      () async {
        final config = await api.appConfig();
        final hosts = List<String>.from(config['apiHosts'] as List);
        expect(hosts.length, greaterThanOrEqualTo(5));
        for (var index = 0; index < hosts.length; index++) {
          await api.saveApiHost('$index');
          expect(await api.loadApiHost(), hosts[index]);
        }
        final previous = await api.loadApiHost();
        await expectLater(api.saveApiHost('999999'), throwsStateError);
        expect(await api.loadApiHost(), previous);
        final other = await ApiFixture.start();
        addTearDown(other.close);
        await api.saveApiHost(other.origin);
        await api
            .init(); // Re-read persisted selection, not a hard-coded default.
        await api.week(0);
        expect(other.calls.single.uri.path, '/week');
        expect(server.calls, isEmpty);
        await api.saveApiHost(server.origin);
        await api.week(0);
        expect(server.calls.single.uri.path, '/week');
      },
    );

    test(
      'CDN candidates do not collapse to one host and custom CDN is used',
      () async {
        final config = await api.appConfig();
        final hosts = List<String>.from(config['cdnHosts'] as List);
        expect(hosts.length, greaterThan(1));
        for (var index = 0; index < hosts.length; index++) {
          await api.saveCdnHost('$index');
          expect(await api.loadCdnHost(), hosts[index]);
        }
        final previous = await api.loadCdnHost();
        await expectLater(api.saveCdnHost('999999'), throwsStateError);
        expect(await api.loadCdnHost(), previous);
        final other = await ApiFixture.start();
        addTearDown(other.close);
        await api.saveCdnHost(other.origin);
        await api.init();
        final image = await api.jmPhotoImage('selected-cdn.png');
        expect(File(image).existsSync(), isTrue);
        expect(other.calls.single.uri.path, '/media/users/selected-cdn.png');
        expect(server.calls, isEmpty);
      },
    );

    test(
      'week initial page zero and filtered pagination reach the HTTP API',
      () async {
        final week = await api.week(
          0,
        ); // The exact WeekScreen initialization call.
        expect(week.categories.single.id, '1');
        expect(week.types.single.id, '2');
        expect(server.calls.last.uri.path, '/week');
        final content = await api.weekFilter('1', '2', 1);
        expect(content.list.single.id, 101);
        expect(server.calls.last.uri.queryParameters, containsPair('id', '1'));
        expect(
          server.calls.last.uri.queryParameters,
          containsPair('type', '2'),
        );
        await expectLater(api.week(-1), throwsStateError);
      },
    );

    test(
      'favorite listing, folder CRUD, session and daily use real bridge',
      () async {
        final user = await api.login('fixture-user', 'fixture-password');
        expect(user.uid, 42);
        expect(await api.loadUsername(), 'fixture-user');
        expect(await api.loadPassword(), 'fixture-password');
        expect(await api.loadLastLoginUsername(), 'fixture-user');
        expect((await api.favorite()).folderList.single.fid, 17);
        final favorites = await api.favorites(17, 2, 'mr');
        expect(favorites.list.single.id, 101);
        expect(favorites.total, 1);
        final listRequest = server.calls.last;
        expect(listRequest.uri.queryParameters['folder_id'], '17');
        expect(listRequest.uri.queryParameters['page'], '2');
        expect(listRequest.cookie, contains('session=fixture=='));
        await api.createFavoriteFolder('Folder & +?');
        expect(server.calls.last.form['type'], 'add');
        await api.renameFavoriteFolder(17, 'Renamed & +?');
        expect(server.calls.last.form['type'], 'edit');
        expect(server.calls.last.form['folder_name'], 'Renamed & +?');
        await api.comicFavoriteFolderMove(101, 17);
        expect(server.calls.last.form['type'], 'move');
        await api.deleteFavoriteFolder(17);
        expect(server.calls.last.form['type'], 'del');
        expect((await api.setFavorite(101)).status, 'ok');
        expect(await api.daily(42), 'fixture signed');
        expect(server.calls.last.uri.path, '/daily_chk');
        expect(server.calls.last.form['daily_id'], '73');
        expect((await api.preLogin()).preLogin, isTrue);
        await api.logout();
        expect((await api.preLogin()).preSet, isFalse);
        await expectLater(api.favorite(), throwsStateError);
      },
    );

    test(
      'favorite protocol and operation failures propagate instead of empty success',
      () async {
        await api.login('fixture-user', 'fixture-password');
        server.malformedFavorite = true;
        await expectLater(api.favorite(), throwsStateError);
        server.malformedFavorite = false;
        server.failFavoriteAction = true;
        await expectLater(
          api.renameFavoriteFolder(17, 'name'),
          throwsStateError,
        );
        await expectLater(api.setFavorite(101), throwsStateError);
      },
    );

    test(
      'album, chapter and nonempty history preserve reading progress',
      () async {
        expect((await api.album(101)).id, 101);
        expect((await api.chapter(101)).id, 101);
        await api.updateViewLog(101, 101, 4);
        final history = await api.pageViewLog(1);
        expect(history.total, 1);
        expect(history.content.single.id, 101);
        final view = await api.findViewLog(101);
        expect(view!.lastViewChapterId, 101);
        expect(view.lastViewPage, 4);
        await api.album(102, ignoreViewLog: true);
        expect(await api.findViewLog(102), isNull);
        await api.deleteViewLogByComicId(101);
        expect((await api.pageViewLog(1)).total, 0);
        await api.album(103);
        await api.clearViewLog();
        expect(await api.findViewLog(103), isNull);
      },
    );

    test(
      'forum UID filter is forwarded and is isolated in the cache key',
      () async {
        final comments = await api.forum('manhua', null, 42, 1);
        expect(comments.list, hasLength(1));
        expect(server.calls.last.uri.queryParameters['uid'], '42');
        final before = server.calls.length;
        await api.forum('manhua', null, 43, 1);
        expect(server.calls.length, before + 1);
        expect(server.calls.last.uri.queryParameters['uid'], '43');
      },
    );

    test('comment and child comment retain form fields', () async {
      await api.login('fixture-user', 'fixture-password');
      expect((await api.forum('manhua', 101, null, 1)).list, hasLength(1));
      expect((await api.comment(101, 'text & +?')).cid, 7);
      expect(server.calls.last.form['comment'], 'text & +?');
      expect((await api.childComment(101, 'reply', 7)).cid, 7);
      expect(server.calls.last.form['comment_id'], '7');
    });

    test(
      'images and local file helpers operate on synthetic PNG bytes',
      () async {
        expect(await api.getStartupImagePath(), '');
        await api.saveStartupImage(fixturePng);
        final startup = await api.getStartupImagePath();
        expect(File(startup).existsSync(), isTrue);
        expect((await api.imageSize(startup)).w, 1);
        final folder = '${transport.directory.path}/copies';
        await api.mkdirs(folder);
        await api.copyPictureToFolder(folder, startup);
        expect(Directory(folder).listSync().whereType<File>(), hasLength(1));
        for (final path in [
          await api.jm3x4Cover(101),
          await api.jmSquareCover(101),
          await api.jmPageImage(101, '00001.png'),
          await api.jmPhotoImage('fixture.png'),
        ]) {
          expect(File(path).existsSync(), isTrue);
        }
        await api.deleteJmPageImageCache(101, '00001.png');
        await api.deleteStartupImage();
        expect(await api.getStartupImagePath(), '');
        expect(await api.httpGet('${server.origin}/raw'), 'fixture text');
        expect(await api.ping(server.origin), greaterThanOrEqualTo(0));
        expect(await api.pingCdn(server.origin), greaterThanOrEqualTo(0));
        await api.cleanAllCache();
      },
    );

    test(
      'download, every export format and all three import entries round-trip',
      () async {
        expect(await api.allDownloads(), isEmpty);
        expect(await api.downloadById(201), isNull);
        await api.createDownload(
          DownloadCreate(
            album: DownloadCreateAlbum(
              id: 201,
              name: 'Fixture transfer',
              author: ['Fixture'],
              tags: ['fixture'],
              works: [],
              description: 'Synthetic one-pixel book',
            ),
            chapters: [
              DownloadCreateChapter(id: 201, name: 'Chapter', sort: '1'),
            ],
          ),
        );
        expect((await api.downloadById(201))!.album.id, 201);
        for (var i = 0; i < 150; i++) {
          final rows = await api.allDownloads();
          if (rows.single.dlStatus == 1) break;
          if (rows.single.dlStatus == 2) fail('Synthetic download failed');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final downloaded = (await api.allDownloads()).single;
        expect(downloaded.dlStatus, 1);
        expect(downloaded.imageCount, 1);
        expect(downloaded.dledImageCount, 1);
        final page = (await api.dlImageByChapterId(201)).single;
        expect(page.dlStatus, 1);
        expect([page.width, page.height], [1, 1]);

        String folder(String name) =>
            (Directory('${transport.directory.path}/exports/$name')
              ..createSync(recursive: true)).path;
        List<String> paths(dynamic text) =>
            List<String>.from(jsonDecode(text as String) as List);
        final zipped =
            paths(await api.export_jm_zip([201], folder('zip'), false)).single;
        final jmi =
            paths(await api.export_jm_jmi([201], folder('jmi'), false)).single;
        final directory =
            paths(
              await api.export_jm_jpegs([201], folder('directory'), false),
            ).single;
        expect(Directory(directory).existsSync(), isTrue);
        final archives = [
          zipped,
          jmi,
          await api.export_jm_zip_single(
            201,
            folder('zip-single'),
            null,
            false,
          ),
          await api.export_jm_jmi_single(
            201,
            folder('jmi-single'),
            null,
            false,
          ),
          await api.export_jm_jpegs_zip_single(
            201,
            folder('images-zip'),
            null,
            false,
          ),
          await api.export_cbzs_zip_single(201, folder('cbz'), null, false),
          ...paths(await api.export_jm_epub([201], folder('epub'), false)),
          ...paths(
            await api.export_jm_epub_single(
              201,
              folder('epub-single'),
              null,
              false,
            ),
          ),
        ];
        for (final path in archives) {
          final bytes = File(path as String).readAsBytesSync();
          expect(bytes.length, greaterThan(64));
          expect(bytes.take(2), [
            80,
            75,
          ], reason: 'Expected ZIP container: $path');
        }
        for (final path in [
          ...paths(await api.export_jm_pdf(201, folder('pdf'), false)),
          ...paths(await api.export_jm_pdf2(201, folder('pdf-merged'), false)),
        ]) {
          expect(File(path).readAsBytesSync().take(5), [37, 80, 68, 70, 45]);
        }

        final scan = Directory('${transport.directory.path}/import-scan')
          ..createSync();
        File(zipped).copySync('${scan.path}/fixture.jm.zip');
        File(jmi).copySync('${scan.path}/fixture.jmi');
        for (final kind in ['zip', 'jmi', 'directory']) {
          final imported = await NativeTransport.start(binary!, outcomes);
          addTearDown(imported.close);
          await imported.api.saveApiHost(server.origin);
          await imported.api.saveCdnHost(server.origin);
          switch (kind) {
            case 'zip':
              await imported.api.import_jm_zip(zipped);
            case 'jmi':
              await imported.api.import_jm_jmi(jmi);
            case 'directory':
              await imported.api.import_jm_dir(scan.path);
          }
          expect(
            (await imported.api.downloadById(201))!.album.name,
            'Fixture transfer',
          );
          expect((await imported.api.allDownloads()).single.dledImageCount, 1);
          final restoredImage = await imported.api.jmPageImage(
            201,
            '00001.png',
          );
          expect(File(restoredImage).existsSync(), isTrue);
          expect((await imported.api.imageSize(restoredImage)).w, 1);
        }
        await api.renewAllDownloads();
        await api.deleteDownload(201);
        for (var i = 0; i < 100 && await api.downloadById(201) != null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(await api.downloadById(201), isNull);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test('directory import propagates a corrupt archive error', () async {
      final folder = Directory('${transport.directory.path}/bad-import')
        ..createSync();
      File(
        '${folder.path}/broken.jm.zip',
      ).writeAsStringSync('not a zip archive');
      await expectLater(api.import_jm_dir(folder.path), throwsStateError);
      expect(await api.allDownloads(), isEmpty);
    });

    test(
      'raw HTTP failure is an error rather than a successful response body',
      () async {
        server.davGetStatus = 503;
        await expectLater(
          api.httpGet('${server.origin}/dav'),
          throwsStateError,
        );
      },
    );

    test('WebDAV upload only writes and download only reads', () async {
      await api.album(101);
      final params = {
        'url': '${server.origin}/dav',
        'username': 'fixture',
        'password': 'fixture',
        'direction': 'Upload',
      };
      server.calls.clear();
      await api.webDavSync(params);
      expect(server.calls.map((call) => call.method), ['PUT']);
      expect(server.davDocument, contains('"id":101'));
      await api.album(
        102,
      ); // Download must replace, not merge, this local-only row.
      server.calls.clear();
      await api.webDavSync({...params, 'direction': 'Download'});
      expect(server.calls.map((call) => call.method), ['GET']);
      expect((await api.pageViewLog(1)).content.single.id, 101);
      server.calls.clear();
      await api.webDavSync({...params, 'direction': 'Merge'});
      expect(server.calls.map((call) => call.method), ['GET', 'PUT']);
    });

    test(
      'WebDAV legacy direction aliases and omitted direction stay compatible',
      () async {
        final params = {
          'url': '${server.origin}/dav',
          'username': '',
          'password': '',
        };
        await api.webDavSync({...params, 'direction': 'Up'});
        expect(server.calls.map((call) => call.method), ['PUT']);
        server.calls.clear();
        await api.webDavSync({...params, 'direction': 'Down'});
        expect(server.calls.map((call) => call.method), ['GET']);
        server.calls.clear();
        await api.webDavSync(params);
        expect(server.calls.map((call) => call.method), ['GET', 'PUT']);
      },
    );

    test(
      'malformed WebDAV and database conflicts preserve existing local history',
      () async {
        final params = {
          'url': '${server.origin}/dav',
          'username': '',
          'password': '',
        };
        await api.album(101);
        await api.webDavSync({...params, 'direction': 'Upload'});
        final valid = server.davDocument!;
        await api.album(102);
        server.davDocument = '$valid\n{broken';
        for (final direction in ['Download', 'Merge']) {
          server.calls.clear();
          await expectLater(
            api.webDavSync({...params, 'direction': direction}),
            throwsStateError,
          );
          expect(server.calls.map((call) => call.method), ['GET']);
          expect((await api.pageViewLog(1)).total, 2);
        }
        server.davDocument = '$valid\n$valid';
        await expectLater(
          api.webDavSync({...params, 'direction': 'Download'}),
          throwsStateError,
        );
        expect((await api.pageViewLog(1)).total, 2);
      },
    );

    test('WebDAV failed read never overwrites the remote document', () async {
      server.davGetStatus = 403;
      await expectLater(
        api.webDavSync({
          'url': '${server.origin}/dav',
          'username': '',
          'password': '',
          'direction': 'Merge',
        }),
        throwsStateError,
      );
      expect(server.calls.map((call) => call.method), ['GET']);
    });

    test(
      'retired interfaces return explicit errors, not successful placeholders',
      () async {
        for (final method in retired) {
          await expectLater(
            api.backend.invoke(method, ''),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                contains('LEGACY_SERVICE_REMOVED'),
              ),
            ),
          );
        }
        await expectLater(
          api.backend.invoke('fixture_unknown_method', ''),
          throwsStateError,
        );
      },
    );
  }, skip: binary == null);

  tearDownAll(() {
    if (binary == null) return;
    final source = File('lib/basic/methods.dart').readAsStringSync();
    final expected =
        RegExp(
          r'_invoke\(\s*"([^"]+)"',
        ).allMatches(source).map((match) => match.group(1)!).toSet();
    final missing = expected.difference(outcomes.keys.toSet()).toList()..sort();
    final report = {
      'scope':
          'Synthetic loopback HTTP and new local SQLite through real Dart/Rust',
      'frontend_methods': expected.length,
      'invoked_frontend_methods':
          expected.intersection(outcomes.keys.toSet()).length,
      'missing': missing,
      'outcomes': {
        for (final name in outcomes.keys.toList()..sort())
          name: outcomes[name]!.toList()..sort(),
      },
      'live_service_validation': false,
    };
    final output = Platform.environment['JASMINE_API_AUDIT_REPORT'];
    if (output != null) {
      File(
        output,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
    if (Platform.environment['JASMINE_REQUIRE_API_COVERAGE'] == '1') {
      expect(
        missing,
        isEmpty,
        reason: 'Every frontend bridge call needs a runtime case',
      );
    }
  });
}
