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
    },
  );
}
