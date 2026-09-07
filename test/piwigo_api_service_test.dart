import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upa_wallpaper_manager/services/piwigo_api_service.dart';

/// A stand-in Piwigo, so the protections meant to spare a real gallery can be
/// checked without touching one.
class _FakeGallery {
  final HttpServer server;
  final List<Uri> requests = [];
  final List<DateTime> times = [];

  /// Answers everything with an error, the way a gallery under water does.
  bool failing = false;

  /// How many photos the album claims to hold.
  int totalCount;

  _FakeGallery._(this.server, this.totalCount);

  static Future<_FakeGallery> start({int totalCount = 1200}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gallery = _FakeGallery._(server, totalCount);
    server.listen(gallery._handle);
    return gallery;
  }

  String get baseUrl => 'http://127.0.0.1:${server.port}/gallery/';

  Future<void> _handle(HttpRequest request) async {
    requests.add(request.uri);
    times.add(DateTime.now());

    if (failing) {
      request.response.statusCode = 504;
      await request.response.close();
      return;
    }

    final page = int.tryParse(request.uri.queryParameters['page'] ?? '0') ?? 0;
    final perPage =
        int.tryParse(request.uri.queryParameters['per_page'] ?? '500') ?? 500;
    final remaining = (totalCount - page * perPage).clamp(0, perPage);

    request.response.headers.contentType = ContentType.json;
    request.response.write(
      json.encode({
        'stat': 'ok',
        'result': {
          'paging': {'total_count': totalCount, 'count': remaining},
          'images': [
            for (var i = 0; i < remaining; i++)
              {
                'id': page * perPage + i,
                'file': 'photo_${page * perPage + i}.jpg',
                'name': 'Photo ${page * perPage + i}',
                'element_url': 'http://example.invalid/photo.jpg',
              },
          ],
        },
      }),
    );
    await request.response.close();
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  test('requests to a gallery are spaced out', () async {
    final gallery = await _FakeGallery.start(totalCount: 1200);
    addTearDown(gallery.stop);

    final api = PiwigoApiService();
    await api.getThemeImages(1, baseUrl: gallery.baseUrl);

    expect(gallery.requests.length, 3);
    final gap = gallery.times[1].difference(gallery.times[0]);
    expect(gap.inMilliseconds, greaterThanOrEqualTo(350));
  });

  test('a whole gallery added as a theme is read one page deep', () async {
    final gallery = await _FakeGallery.start(totalCount: 3000000);
    addTearDown(gallery.stop);

    final api = PiwigoApiService();
    final images = await api.getThemeImages(
      1,
      baseUrl: gallery.baseUrl,
      recursive: true,
    );

    expect(gallery.requests.length, 1);
    expect(images.length, 500);
  });

  test('no album is paged into beyond the ceiling', () async {
    // Just under the "whole gallery" mark, so only the page cap applies.
    final gallery = await _FakeGallery.start(totalCount: 19000);
    addTearDown(gallery.stop);

    final api = PiwigoApiService();
    await api.getThemeImages(1, baseUrl: gallery.baseUrl);

    expect(gallery.requests.length, PiwigoApiService.maxPagesPerTheme);
  });

  test('a failing gallery is left alone instead of being retried', () async {
    final gallery = await _FakeGallery.start();
    addTearDown(gallery.stop);
    gallery.failing = true;

    final api = PiwigoApiService();
    // Three themes in a row, as the start-up pass would do.
    for (var theme = 0; theme < 3; theme++) {
      await api.getThemeImages(theme, baseUrl: gallery.baseUrl);
    }

    // Two attempts, then silence — the gallery is not asked again.
    expect(gallery.requests.length, 2);

    // Until the user asks for something themselves.
    api.forgetFailures(gallery.baseUrl);
    gallery.failing = false;
    final images = await api.getThemeImages(9, baseUrl: gallery.baseUrl);
    expect(images, isNotEmpty);
  });
}
