import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'piwigo_api_service.dart';

/// Photos the gallery marks as unwanted on a phone, via its "NoMobile" tag.
///
/// The list is kept on disk so a start without network still hides them:
/// showing a banned photo once because the app was offline would defeat the
/// point of the tag.
class HiddenPhotosService {
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// How long the list of tagged photos is trusted before asking again.
  static const Duration maxAge = Duration(hours: 12);

  Set<int> _ids = const {};
  DateTime? _fetchedAt;
  late File _file;
  bool _ready = false;

  Set<int> get ids => _ids;

  /// True when the gallery should be asked for the list again.
  bool get isStale {
    final fetched = _fetchedAt;
    return fetched == null || DateTime.now().difference(fetched) > maxAge;
  }

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/hidden_photos.json');
    _ready = true;
    try {
      if (await _file.exists()) {
        final data = json.decode(await _file.readAsString());
        final map = data as Map<String, dynamic>;
        final list = map['ids'] as List<dynamic>?;
        _ids = {...?list?.whereType<int>()};
        _fetchedAt = DateTime.tryParse(map['fetchedAt'] as String? ?? '');
        _log.i('Hidden photos: ${_ids.length} known from a previous run');
      }
    } catch (e) {
      _log.w('Could not read the hidden photo list: $e');
    }
  }

  /// Asks the gallery for the current list.
  ///
  /// Returns the ids that were not hidden before, so the caller can clear
  /// them out of the cache. Null when the gallery could not be reached or has
  /// no such tag, which leaves the previous list in place.
  Future<Set<int>?> refresh(PiwigoApiService api) async {
    final fetched = await api.getTaggedImageIds(
      PiwigoApiService.noMobileTag,
      baseUrl: PiwigoApiService.defaultUpaBaseUrl,
    );
    if (fetched == null) return null;

    final added = fetched.difference(_ids);
    _ids = fetched;
    _fetchedAt = DateTime.now();
    await _save();
    if (added.isNotEmpty) {
      _log.i('Hidden photos: ${added.length} newly tagged');
    }
    return added;
  }

  Future<void> _save() async {
    if (!_ready) return;
    try {
      await _file.writeAsString(
        json.encode({
          'ids': _ids.toList(),
          'fetchedAt': _fetchedAt?.toIso8601String(),
        }),
      );
    } catch (e) {
      _log.w('Could not save the hidden photo list: $e');
    }
  }
}
