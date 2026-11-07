import 'dart:convert';
import 'dart:io';
import 'package:daily_ledger/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'semantic version comparison handles patch, minor and major changes',
    () {
      expect(isNewerVersion('v0.2.1', '0.2.0'), isTrue);
      expect(isNewerVersion('v0.10.0', '0.2.9'), isTrue);
      expect(isNewerVersion('v1.0.0', '0.9.9'), isTrue);
      expect(isNewerVersion('v0.2.0', '0.2.0'), isFalse);
      expect(isNewerVersion('v0.1.9', '0.2.0'), isFalse);
      expect(() => isNewerVersion('latest', '0.2.0'), throwsFormatException);
    },
  );
  test(
    'only stable releases and the project download destination are accepted',
    () {
      final release = GithubRelease.fromJson({
        'tag_name': 'v0.3.0',
        'body': 'Changes',
        'html_url': 'https://invalid.example',
      });
      expect(
        release.url.toString(),
        'https://github.com/donia257/gougou-wallet/releases/tag/v0.3.0',
      );
      expect(
        () =>
            GithubRelease.fromJson({'tag_name': 'v0.3.0', 'prerelease': true}),
        throwsFormatException,
      );
      expect(
        () => GithubRelease.fromJson({'tag_name': 'v0.3.0', 'draft': true}),
        throwsFormatException,
      );
      expect(
        GithubRelease.fromRedirect(
          '$githubRepositoryUrl/releases/tag/v0.3.0',
        ).tag,
        'v0.3.0',
      );
      expect(
        () => GithubRelease.fromRedirect(
          'https://invalid.example/releases/tag/v0.3.0',
        ),
        throwsFormatException,
      );
      expect(
        () => GithubRelease.fromRedirect(
          'https://github.com/other/repo/releases/tag/v0.3.0',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'API limits and stale API responses fall back to the public release redirect',
    () async {
      for (final status in [403, 429, 404]) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <String>[];
        server.listen((request) async {
          requests.add(request.uri.path);
          if (request.uri.path.startsWith('/api.github.com/')) {
            request.response.statusCode = status;
            request.response.write('rate limited');
          } else {
            request.response.statusCode = 302;
            request.response.headers.set(
              HttpHeaders.locationHeader,
              '$githubRepositoryUrl/releases/tag/v0.3.0',
            );
          }
          await request.response.close();
        });
        try {
          final release = await UpdateService(
            clientFactory: () => RoutedClient(server.port),
          ).latest();
          expect(release.tag, 'v0.3.0');
          expect(requests.length, 2);
          expect(
            requests.last,
            '/github.com/donia257/gougou-wallet/releases/latest',
          );
        } finally {
          await server.close(force: true);
        }
      }
    },
  );

  test('a successful API response uses its release notes directly', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'tag_name': 'v0.3.0', 'body': 'release notes'}),
      );
      await request.response.close();
    });
    try {
      final release = await UpdateService(
        clientFactory: () => RoutedClient(server.port),
      ).latest();
      expect(release.notes, 'release notes');
      expect(requests, 1);
    } finally {
      await server.close(force: true);
    }
  });
}

class RoutedClient implements HttpClient {
  RoutedClient(this.port);
  final int port;
  final HttpClient delegate = HttpClient();
  @override
  Future<HttpClientRequest> getUrl(Uri url) => delegate.getUrl(
    Uri.parse('http://127.0.0.1:$port/${url.host}${url.path}'),
  );
  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
