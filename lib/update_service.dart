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
  Future<GithubRelease> latest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
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
    if (response.statusCode == 404) throw const HttpException('暂未找到正式版本');
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const HttpException('GitHub 查询较频繁，请稍后再试');
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
}
