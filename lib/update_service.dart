import 'dart:async';
import 'dart:convert';
import 'dart:io';

const githubRepository = 'donia257/gougou-wallet';
const githubRepositoryUrl = 'https://github.com/$githubRepository';

List<int> versionParts(String version) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
  if (match == null) throw const FormatException('GitHub 版本信息格式有误');
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

bool isNewerVersion(String candidate, String installed) {
  final remote = versionParts(candidate);
  final local = versionParts(installed);
  for (var i = 0; i < 3; i++) {
    if (remote[i] != local[i]) return remote[i] > local[i];
  }
  return false;
}

class GithubRelease {
  const GithubRelease({required this.tag, required this.notes});
  final String tag;
  final String notes;
  Uri get url => Uri.parse(
    '$githubRepositoryUrl/releases/tag/${Uri.encodeComponent(tag)}',
  );
  factory GithubRelease.fromRedirect(String? location) {
    if (location == null) throw const FormatException('暂未找到正式版本');
    final target = Uri.parse(githubRepositoryUrl).resolve(location);
    final segments = target.pathSegments;
    if (target.scheme != 'https' ||
        target.host != 'github.com' ||
        target.userInfo.isNotEmpty ||
        target.port != 443 ||
        segments.length != 5 ||
        segments.take(4).join('/') != '$githubRepository/releases/tag') {
      throw const FormatException('GitHub 更新地址有误');
    }
    versionParts(segments.last);
    return GithubRelease(tag: segments.last, notes: '');
  }
  factory GithubRelease.fromJson(Map<String, dynamic> data) {
    if (data['draft'] == true || data['prerelease'] == true) {
      throw const FormatException('暂未找到正式版本');
    }
    final tag = data['tag_name'] as String;
    versionParts(tag);
    return GithubRelease(
      tag: tag,
      notes: (data['body'] as String? ?? '').trim(),
    );
  }
}

class UpdateService {
  UpdateService({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClient;
  final HttpClient Function() _clientFactory;
  static HttpClient _defaultClient() =>
      HttpClient()..connectionTimeout = const Duration(seconds: 8);
  Future<GithubRelease> latest() async {
    final client = _clientFactory();
    try {
      return await _fetch(client).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const HttpException('连接 GitHub 超时，请稍后重试');
    } on SocketException {
      throw const HttpException('暂时无法连接 GitHub，请检查网络后重试');
    } finally {
      client.close(force: true);
    }
  }

  Future<GithubRelease> _fetch(HttpClient client) async {
    final request = await client.getUrl(
      Uri.parse(
        'https://api.github.com/repos/$githubRepository/releases/latest',
      ),
    );
    request.headers.set('User-Agent', 'gougou-wallet');
    request.headers.set('Accept', 'application/vnd.github+json');
    request.headers.set('X-GitHub-Api-Version', '2022-11-28');
    final response = await request.close();
    if ([403, 404, 429].contains(response.statusCode)) {
      await response.drain<void>();
      return _fromReleasePage(client);
    }
    if (response.statusCode != 200) {
      throw const HttpException('GitHub 暂时不可用，请稍后重试');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const FormatException('版本信息过大');
      }
      bytes.addAll(chunk);
    }
    return GithubRelease.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );
  }

  Future<GithubRelease> _fromReleasePage(HttpClient client) async {
    final request = await client.getUrl(
      Uri.parse('$githubRepositoryUrl/releases/latest'),
    );
    request.followRedirects = false;
    request.headers.set('User-Agent', 'gougou-wallet');
    final response = await request.close();
    final location = response.headers.value(HttpHeaders.locationHeader);
    await response.drain<void>();
    if (response.statusCode == 404) throw const HttpException('暂未找到正式版本');
    if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
      throw const HttpException('GitHub 暂时不可用，请稍后重试');
    }
    return GithubRelease.fromRedirect(location);
  }
}
