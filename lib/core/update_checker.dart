import 'dart:convert';
import 'dart:io';

const nirangRepositoryUrl = 'https://github.com/bardia-us/niraNG';
const nirangLatestReleaseApi =
    'https://api.github.com/repos/bardia-us/niraNG/releases/latest';

class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  factory SemanticVersion.parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) throw const FormatException('Invalid release version');
    return SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    final majorResult = major.compareTo(other.major);
    if (majorResult != 0) return majorResult;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    return patch.compareTo(other.patch);
  }

  final int major;
  final int minor;
  final int patch;

  @override
  String toString() => '$major.$minor.$patch';
}

class ReleaseCheckResult {
  const ReleaseCheckResult({
    required this.latestVersion,
    required this.releaseUrl,
    required this.updateAvailable,
  });

  final SemanticVersion latestVersion;
  final Uri releaseUrl;
  final bool updateAvailable;
}

class GitHubUpdateChecker {
  const GitHubUpdateChecker();

  Future<ReleaseCheckResult> check(String currentVersion) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(nirangLatestReleaseApi));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'niraNG-update-checker/1.0.6');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('GitHub release check failed');
      }
      final payload = jsonDecode(
        await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 10)),
      );
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid GitHub response');
      }
      final latest = SemanticVersion.parse('${payload['tag_name'] ?? ''}');
      final releaseUrl = Uri.tryParse('${payload['html_url'] ?? ''}');
      if (releaseUrl == null ||
          releaseUrl.scheme != 'https' ||
          releaseUrl.host != 'github.com' ||
          !releaseUrl.path.startsWith('/bardia-us/niraNG/releases/')) {
        throw const FormatException('Invalid release URL');
      }
      return ReleaseCheckResult(
        latestVersion: latest,
        releaseUrl: releaseUrl,
        updateAvailable:
            latest.compareTo(SemanticVersion.parse(currentVersion)) > 0,
      );
    } finally {
      client.close(force: true);
    }
  }
}
