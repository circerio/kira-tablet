import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/comic.dart';
import 'package:kira/utils/bookshelf_update_order.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

Comic _comic(
  String pathWord, {
  required String updated,
  required String latestId,
  required String latestName,
}) => Comic(
  name: pathWord,
  pathWord: pathWord,
  cover: '',
  datetimeUpdated: updated,
  lastChapterId: latestId,
  lastChapterName: latestName,
);

BookshelfItem _item(
  String pathWord, {
  required String updated,
  required String latestId,
  required String latestName,
  String? browseId,
  String? browseName,
}) => BookshelfItem(
  comic: _comic(
    pathWord,
    updated: updated,
    latestId: latestId,
    latestName: latestName,
  ),
  lastBrowseId: browseId,
  lastBrowseName: browseName,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await ReadingHistory.flush();
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'hasUpdate treats a replacement UUID as new even with the same name',
    () {
      final sameId = _item(
        'same-id',
        updated: '2026-10-01T10:00:00Z',
        latestId: 'ch2',
        latestName: '第2話',
        browseId: 'ch2',
        browseName: '第2話',
      );
      final reissuedId = _item(
        'same-name',
        updated: '2026-10-01T10:00:00Z',
        latestId: 'new-ch2-id',
        latestName: '第2話',
        browseId: 'old-ch2-id',
        browseName: '第2話',
      );
      final stale = _item(
        'stale',
        updated: '2026-10-01T10:00:00Z',
        latestId: 'ch2',
        latestName: '第2話',
        browseId: 'ch1',
        browseName: '第1話',
      );
      final neverRead = _item(
        'never-read',
        updated: '2026-10-01T10:00:00Z',
        latestId: 'ch2',
        latestName: '第2話',
      );

      expect(sameId.hasUpdate, isFalse);
      expect(reissuedId.hasUpdate, isTrue);
      expect(stale.hasUpdate, isTrue);
      expect(neverRead.hasUpdate, isFalse);
    },
  );

  test('by-update sort puts unread updates before newer caught-up works', () {
    final caughtNewest = _item(
      'caught-newest',
      updated: '2026-10-02T12:00:00Z',
      latestId: 'a2',
      latestName: 'A2',
      browseId: 'a2',
      browseName: 'A2',
    );
    final unreadNewest = _item(
      'unread-newest',
      updated: '2026-10-01T12:00:00Z',
      latestId: 'b2',
      latestName: 'B2',
      browseId: 'b1',
      browseName: 'B1',
    );
    final unreadOlder = _item(
      'unread-older',
      updated: '2026-09-30T12:00:00Z',
      latestId: 'c2',
      latestName: 'C2',
      browseId: 'c1',
      browseName: 'C1',
    );
    final caughtOlder = _item(
      'caught-older',
      updated: '2026-09-29T12:00:00Z',
      latestId: 'd2',
      latestName: 'D2',
      browseId: 'd2',
      browseName: 'D2',
    );

    final sorted = sortBookshelfByUnreadUpdate([
      caughtOlder,
      caughtNewest,
      unreadOlder,
      unreadNewest,
    ]);

    expect(sorted.map((item) => item.comic.pathWord).toList(), [
      'unread-newest',
      'unread-older',
      'caught-newest',
      'caught-older',
    ]);
  });

  test(
    'local history clears a stale server update badge across groups',
    () async {
      await ReadingHistory.save(
        pathWord: 'local-caught-up',
        group: ReadingHistory.defaultGroup,
        chapterUuid: 'latest',
        chapterName: '最新話',
      );
      await ReadingHistory.flush();

      // Reading an older side chapter later must not erase proof that latest was
      // already read.
      await ReadingHistory.save(
        pathWord: 'local-caught-up',
        group: 'extra',
        chapterUuid: 'side-old',
        chapterName: '番外舊話',
      );
      await ReadingHistory.flush();

      final serverStale = _item(
        'local-caught-up',
        updated: '2026-10-01T12:00:00Z',
        latestId: 'latest',
        latestName: '最新話',
        browseId: 'server-old',
        browseName: '舊話',
      );

      final reconciled = await reconcileBookshelfReadingProgress([serverStale]);
      expect(reconciled.single.lastBrowseId, 'latest');
      expect(reconciled.single.hasUpdate, isFalse);
    },
  );
  test('local-only progress can establish a real unread update', () async {
    await ReadingHistory.save(
      pathWord: 'local-progress',
      chapterUuid: 'ch1',
      chapterName: '第1話',
    );
    await ReadingHistory.flush();

    final noServerBrowse = _item(
      'local-progress',
      updated: '2026-10-01T12:00:00Z',
      latestId: 'ch2',
      latestName: '第2話',
    );

    final reconciled = await reconcileBookshelfReadingProgress([
      noServerBrowse,
    ]);
    expect(reconciled.single.lastBrowseId, 'ch1');
    expect(reconciled.single.hasUpdate, isTrue);
  });
}
