import 'dart:convert';
import 'dart:io';

class OfficialHomeBanner {
  final String cover;
  final String? pathWord;

  const OfficialHomeBanner({required this.cover, this.pathWord});
}

Future<List<OfficialHomeBanner>> fetchOfficialHomeBanners({
  int limit = 5,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(
      Uri.parse('https://www.mangacopy.com/'),
    );
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 Chrome/150.0.0.0 Safari/537.36',
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) return const [];
    final body = await utf8.decoder.bind(response).join();
    final result = <OfficialHomeBanner>[];
    final imageTags = RegExp(
      r'<img\b[^>]*>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(body);

    for (final match in imageTags) {
      if (result.length >= limit) break;
      final tag = match.group(0)!;
      final classMatch = RegExp(
        r'''class=["']([^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(tag);
      if (!(classMatch?.group(1) ?? '').toLowerCase().contains('swiper')) {
        continue;
      }

      final srcMatch = RegExp(
        r'''(?:src|data-src|data-original)=["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(tag);
      final cover = srcMatch?.group(1);
      if (cover == null || cover.isEmpty) continue;
      final start = match.start > 1600 ? match.start - 1600 : 0;
      final prefix = body.substring(start, match.start);
      final anchors = RegExp(
        r'''<a\b[^>]*href=["']([^"']+)["'][^>]*>''',
        caseSensitive: false,
      ).allMatches(prefix).toList();
      final href = anchors.isEmpty ? null : anchors.last.group(1);
      final pathMatch = href == null
          ? null
          : RegExp(r'''/comic/([^/?#"']+)''').firstMatch(href);

      result.add(
        OfficialHomeBanner(cover: cover, pathWord: pathMatch?.group(1)),
      );
    }
    return result;
  } catch (_) {
    return const [];
  } finally {
    client.close(force: true);
  }
}
