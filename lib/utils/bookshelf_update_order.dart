import '../models/comic.dart';
import 'reading_history.dart';

/// Reconciles the server bookshelf progress with local reading history.
///
/// Server progress is still authoritative when present, except that local
/// history may prove that the current latest chapter has already been read.
/// If the server has no browse record at all, a local record supplies the
/// missing progress so unread-update detection can still work.
Future<List<BookshelfItem>> reconcileBookshelfReadingProgress(
  List<BookshelfItem> items,
) async {
  if (items.isEmpty) return items;

  final progress = await ReadingHistory.progressForComics(
    items.map((item) => item.comic.pathWord),
  );

  return [
    for (final item in items)
      _reconcileItem(item, progress[item.comic.pathWord]),
  ];
}

BookshelfItem _reconcileItem(BookshelfItem item, ComicReadingProgress? local) {
  if (local == null) return item;

  final latestId = item.comic.lastChapterId?.trim() ?? '';
  if (latestId.isNotEmpty && local.readChapterUuids.contains(latestId)) {
    return BookshelfItem(
      comic: item.comic,
      lastBrowseId: latestId,
      lastBrowseName: item.comic.lastChapterName ?? item.lastBrowseName,
    );
  }

  final serverBrowseId = item.lastBrowseId?.trim() ?? '';
  final serverBrowseName = item.lastBrowseName?.trim() ?? '';
  if (serverBrowseId.isNotEmpty || serverBrowseName.isNotEmpty) return item;

  final localLatest = local.latest;
  if (localLatest.chapterUuid.isEmpty && localLatest.chapterName.isEmpty) {
    return item;
  }
  return BookshelfItem(
    comic: item.comic,
    lastBrowseId: localLatest.chapterUuid.isEmpty
        ? item.lastBrowseId
        : localLatest.chapterUuid,
    lastBrowseName: localLatest.chapterName.isEmpty
        ? item.lastBrowseName
        : localLatest.chapterName,
  );
}

/// "By update" means unread updates first, then the official update time.
///
/// Both the unread and caught-up partitions are ordered by datetime_updated
/// descending. Original order is the final stable tiebreaker.
List<BookshelfItem> sortBookshelfByUnreadUpdate(Iterable<BookshelfItem> items) {
  final indexed = items.toList(growable: false).asMap().entries.toList();
  indexed.sort((a, b) {
    final aUnread = a.value.hasUpdate;
    final bUnread = b.value.hasUpdate;
    if (aUnread != bUnread) return aUnread ? -1 : 1;

    final timeOrder = _compareOfficialUpdateDesc(
      a.value.comic.datetimeUpdated,
      b.value.comic.datetimeUpdated,
    );
    if (timeOrder != 0) return timeOrder;
    return a.key.compareTo(b.key);
  });
  return indexed.map((entry) => entry.value).toList(growable: false);
}

int _compareOfficialUpdateDesc(String? a, String? b) {
  final aRaw = a?.trim() ?? '';
  final bRaw = b?.trim() ?? '';
  final aDate = DateTime.tryParse(aRaw);
  final bDate = DateTime.tryParse(bRaw);

  if (aDate != null && bDate != null) return bDate.compareTo(aDate);
  if (aDate != null) return -1;
  if (bDate != null) return 1;

  if (aRaw.isEmpty && bRaw.isEmpty) return 0;
  if (aRaw.isEmpty) return 1;
  if (bRaw.isEmpty) return -1;
  return bRaw.compareTo(aRaw);
}
