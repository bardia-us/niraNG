import 'dart:convert';
import 'dart:io';

const nirangRepositoryUrl = 'https://github.com/bardia-us/niraNG';
const nirangLatestReleaseApi =
    'https://api.github.com/repos/bardia-us/niraNG/releases/latest';
const nirangReleaseByTagApi =
    'https://api.github.com/repos/bardia-us/niraNG/releases/tags/';

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
    required this.assets,
    this.mandatory = false,
  });

  final SemanticVersion latestVersion;
  final Uri releaseUrl;
  final bool updateAvailable;
  final List<ReleaseAsset> assets;
  final bool mandatory;

  ReleaseAsset? assetForAbis(List<String> supportedAbis) {
    for (final abi in supportedAbis) {
      final normalized = abi.toLowerCase();
      for (final asset in assets) {
        if (asset.matchesAbi(normalized)) return asset;
      }
    }
    for (final asset in assets) {
      if (asset.name.toLowerCase().contains('universal')) return asset;
    }
    return null;
  }
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.sha256,
  });

  final String name;
  final Uri downloadUrl;
  final int size;
  final String? sha256;

  bool matchesAbi(String abi) {
    final lower = name.toLowerCase();
    return switch (abi) {
      'arm64-v8a' => lower.contains('arm64-v8a') || lower.contains('arm64'),
      'armeabi-v7a' => lower.contains('armeabi-v7a') || lower.contains('armv7'),
      'x86_64' => lower.contains('x86_64') || lower.contains('x64'),
      _ => lower.contains(abi),
    };
  }
}

class GitHubUpdateChecker {
  const GitHubUpdateChecker();

  Future<ReleaseCheckResult> check(String currentVersion) async {
    final payload = await _fetch(
      Uri.parse(nirangLatestReleaseApi),
      currentVersion,
    );
    return parseGitHubRelease(payload, currentVersion);
  }

  Future<BilingualReleaseNotes> releaseNotes(String version) async {
    final tag = version.startsWith('v') ? version : 'v$version';
    final payload = await _fetch(
      Uri.parse('$nirangReleaseByTagApi${Uri.encodeComponent(tag)}'),
      version,
    );
    return parseBilingualReleaseNotes('${payload['body'] ?? ''}');
  }

  Future<Map<String, dynamic>> _fetch(Uri uri, String currentVersion) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(
          HttpHeaders.userAgentHeader,
          'niraNG-update-checker/$currentVersion',
        );
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
      return payload;
    } finally {
      client.close(force: true);
    }
  }
}

class BilingualReleaseNotes {
  const BilingualReleaseNotes({required this.english, required this.persian});

  final String english;
  final String persian;

  String forLanguage(String language) => language == 'fa'
      ? (persian.isNotEmpty ? persian : english)
      : (english.isNotEmpty ? english : persian);
}

BilingualReleaseNotes parseBilingualReleaseNotes(String body) {
  final sections = <String, StringBuffer>{
    'en': StringBuffer(),
    'fa': StringBuffer(),
  };
  String? current;
  for (final line in body.replaceAll('\r\n', '\n').split('\n')) {
    final heading = line.trim().toLowerCase().replaceAll(
      RegExp(r'[#:*_\s]'),
      '',
    );
    if ({'english', 'en', 'انگلیسی'}.contains(heading)) {
      current = 'en';
      continue;
    }
    if ({'فارسی', 'persian', 'fa', 'farsi'}.contains(heading)) {
      current = 'fa';
      continue;
    }
    if (current != null) sections[current]!.writeln(line);
  }
  final english = sections['en']!.toString().trim();
  final persian = sections['fa']!.toString().trim();
  if (english.isEmpty && persian.isEmpty) {
    return BilingualReleaseNotes(english: body.trim(), persian: '');
  }
  return BilingualReleaseNotes(english: english, persian: persian);
}

ReleaseCheckResult parseGitHubRelease(
  Map<String, dynamic> payload,
  String currentVersion,
) {
  final latest = SemanticVersion.parse('${payload['tag_name'] ?? ''}');
  final releaseUrl = Uri.tryParse('${payload['html_url'] ?? ''}');
  if (!_isOfficialReleaseUrl(releaseUrl)) {
    throw const FormatException('Invalid release URL');
  }
  final assets = <ReleaseAsset>[];
  for (final raw
      in payload['assets'] is List ? payload['assets'] as List : const []) {
    if (raw is! Map) continue;
    final name = '${raw['name'] ?? ''}'.trim();
    final url = Uri.tryParse('${raw['browser_download_url'] ?? ''}');
    final size = raw['size'] is num ? (raw['size'] as num).toInt() : 0;
    final digest = '${raw['digest'] ?? ''}'.toLowerCase();
    if (!name.toLowerCase().endsWith('.apk') ||
        !_isOfficialDownloadUrl(url) ||
        size <= 0 ||
        size > 250 * 1024 * 1024) {
      continue;
    }
    assets.add(
      ReleaseAsset(
        name: name,
        downloadUrl: url!,
        size: size,
        sha256: RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(digest)
            ? digest.substring(7)
            : null,
      ),
    );
  }
  return ReleaseCheckResult(
    latestVersion: latest,
    releaseUrl: releaseUrl!,
    updateAvailable:
        latest.compareTo(SemanticVersion.parse(currentVersion)) > 0,
    assets: List.unmodifiable(assets),
  );
}

bool _isOfficialReleaseUrl(Uri? uri) =>
    uri != null &&
    uri.scheme == 'https' &&
    uri.host == 'github.com' &&
    uri.path.startsWith('/bardia-us/niraNG/releases/');

bool _isOfficialDownloadUrl(Uri? uri) =>
    _isOfficialReleaseUrl(uri) &&
    uri!.path.startsWith('/bardia-us/niraNG/releases/download/');
