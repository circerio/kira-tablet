import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/comic.dart';
import 'reading_history.dart';

typedef NewUploadResolver =
    Future<Set<String>> Function(Comic comic, DateTime? since);

const _uploadSnapshotPrefix = 'bookshelf_upload_snapshot_v2_';

String _snapshotKey(String pathWord) =>
    '$_uploadSnapshotPrefix${Uri.encodeComponent(pathWord)}';

String _comicUploadMarker(Comic comic) {
  final updated = comic.datetimeUpdated?.trim() ?? '';
  final lastId = comic.lastChapterId?.trim() ?? '';
  return '$updated|$lastId';
}

DateTime? _markerDate(String marker) {
  final separator = marker.indexOf('|');
  final raw = separator < 0 ? marker : marker.substring(0, separator);
  return DateTime.tryParse(raw.trim());
}

Future<List<BookshelfItem>> reconcileBookshelfUploadUpdates(
  List<BookshelfItem> items, {
  required NewUploadResolver resolveNewUploads,
}) async {
  if (items.isEmpty) return items;

  final progress = await ReadingHistory.progressForComics(
    items.map((item) => item.comic.pathWord),
  );
  final prefs = await SharedPreferences.getInstance();
  final result = <BookshelfItem>[];

  for (final item in items) {
    final pathWord = item.comic.pathWord;
    final marker = _comicUploadMarker(item.comic);
    final snapshot = _readSnapshot(prefs, pathWord);
    final readIds = _readIds(item, progress[pathWord]);

    if (snapshot == null) {
      // Migration baseline: existing books keep legacy semantics without a
      // one-time fan-out across every group. The next official update marker
      // upgrades this comic to strict cross-group upload tracking.
      await _writeSnapshot(
        prefs,
        pathWord,
        _UploadSnapshot(
          marker: marker,
          strict: false,
          pendingUploadIds: const <String>{},
        ),
      );
      result.add(_withOverride(item, null));
      continue;
    }

    final remainingPending = <String>{
      ...snapshot.pendingUploadIds.where((id) => !readIds.contains(id)),
    };

    if (snapshot.marker == marker) {
      if (!snapshot.strict) {
        result.add(_withOverride(item, null));
        continue;
      }
      if (!_sameSet(remainingPending, snapshot.pendingUploadIds)) {
        await _writeSnapshot(
          prefs,
          pathWord,
          _UploadSnapshot(
            marker: snapshot.marker,
            strict: true,
            pendingUploadIds: remainingPending,
          ),
        );
      }
      result.add(_withOverride(item, remainingPending.isNotEmpty));
      continue;
    }

    try {
      final newIds = await resolveNewUploads(
        item.comic,
        _markerDate(snapshot.marker),
      );
      remainingPending.addAll(newIds.where((id) => !readIds.contains(id)));

      await _writeSnapshot(
        prefs,
        pathWord,
        _UploadSnapshot(
          marker: marker,
          strict: true,
          pendingUploadIds: remainingPending,
        ),
      );
      result.add(_withOverride(item, remainingPending.isNotEmpty));
    } catch (_) {
      // Keep the previous marker so the next refresh retries this exact update.
      // Existing pending uploads can still be cleared as the user reads them.
      if (snapshot.strict) {
        if (!_sameSet(remainingPending, snapshot.pendingUploadIds)) {
          await _writeSnapshot(
            prefs,
            pathWord,
            _UploadSnapshot(
              marker: snapshot.marker,
              strict: true,
              pendingUploadIds: remainingPending,
            ),
          );
        }
        result.add(_withOverride(item, remainingPending.isNotEmpty));
      } else {
        result.add(_withOverride(item, null));
      }
    }
  }

  return result;
}

Set<String> _readIds(
  BookshelfItem item,
  ComicReadingProgress? progress,
) => <String>{
  ...?progress?.readChapterUuids,
  if ((item.lastBrowseId?.trim() ?? '').isNotEmpty) item.lastBrowseId!.trim(),
};

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

BookshelfItem _withOverride(BookshelfItem item, bool? value) => BookshelfItem(
  comic: item.comic,
  lastBrowseId: item.lastBrowseId,
  lastBrowseName: item.lastBrowseName,
  hasUpdateOverride: value,
);

_UploadSnapshot? _readSnapshot(SharedPreferences prefs, String pathWord) {
  final raw = prefs.getString(_snapshotKey(pathWord));
  if (raw == null) return null;
  try {
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    final marker = json['marker']?.toString() ?? '';
    final strict = json['strict'] == true;
    final ids =
        (json['pendingUploadIds'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toSet() ??
        const <String>{};
    return _UploadSnapshot(
      marker: marker,
      strict: strict,
      pendingUploadIds: ids,
    );
  } catch (_) {
    return null;
  }
}

Future<void> _writeSnapshot(
  SharedPreferences prefs,
  String pathWord,
  _UploadSnapshot snapshot,
) async {
  await prefs.setString(
    _snapshotKey(pathWord),
    jsonEncode({
      'marker': snapshot.marker,
      'strict': snapshot.strict,
      'pendingUploadIds': snapshot.pendingUploadIds.toList()..sort(),
    }),
  );
}

class _UploadSnapshot {
  final String marker;
  final bool strict;
  final Set<String> pendingUploadIds;

  const _UploadSnapshot({
    required this.marker,
    required this.strict,
    required this.pendingUploadIds,
  });
}
