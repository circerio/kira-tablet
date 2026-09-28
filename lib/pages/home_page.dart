import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../providers/app_providers.dart';
import '../providers/repository_providers.dart';
import '../repositories/manga_home_repository.dart';
import '../routing/app_router.dart';
import '../routing/branch_activation.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/app_logger.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/official_home_banners.dart';
import '../utils/settings_rebuild_guard.dart';
import '../utils/time_format.dart';
import '../widgets/comic_card_surface.dart';
import '../widgets/comic_hero_tags.dart';
import '../widgets/cover_placeholder.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/section_header.dart';

part 'home/home_banner.dart';
part 'home/home_cards.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

const _mangaHomeCardWidth = 112.0;
const _mangaHomeCardAspectRatio = 0.55;
const _mangaHomeCardSpacing = 12.0;

/// 卡片最大宽度随可用宽度增大：手机保持 112，宽屏（横屏/桌面窗口）
/// 提到 150，避免大屏幕上一排挤十几张小卡片。
double _mangaHomeCardMaxExtent(double availableWidth) {
  if (availableWidth >= 1100) return 190.0;
  if (availableWidth >= 720) return 170.0;
  return _mangaHomeCardWidth;
}

class _HomePageState extends ConsumerState<HomePage>
    with SettingsRebuildGuard<HomePage>, BranchDeferredInit {
  MangaHomeRepository get _repo => ref.read(mangaHomeRepositoryProvider);
  UserManager get _user => ref.read(userManagerProvider);
  final _api = ApiClient();
  MangaHome? _home;
  CopyMangaHome? _copyHome;
  String? _activeSource; // 当前已加载的数据源
  List<Comic> _rankingPreview = [];
  List<Comic> _copyRecommendations = const [];
  List<OfficialHomeBanner> _officialWebBanners = const [];

  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user.addListener(handleSettingsChanged);
    _activeSource = _user.mangaHomeSource;
    deferInitialLoadToBranchActivation();
  }

  @override
  void onBranchFirstActivated() {
    _loadFromCache();
    _load();
    unawaited(_loadOfficialWebBanners());
  }

  @override
  void dispose() {
    _user.removeListener(handleSettingsChanged);
    super.dispose();
  }

  /// 首页只用到这两项；其余设置（阅读器亮度等）变化时不再重建整棵树。
  @override
  Object watchedSettings() => (_user.bannerVisible, _user.mangaHomeSource);

  @override
  void onWatchedSettingsChanged() {
    // 数据源切换时重新加载对应数据；分支未激活过时只更新目标源，
    // 首次加载回调会按当前源拉取。
    if (_activeSource != _user.mangaHomeSource) {
      _activeSource = _user.mangaHomeSource;
      if (branchInitialLoadStarted) {
        _loading = true;
        _error = null;
        _home = null;
        _copyHome = null;
        _copyRecommendations = const [];
        _loadFromCache();
        _load();
      }
    }
    setState(() {});
  }

  bool get _isCopySource => _user.mangaHomeSource == 'copy';

  Future<void> _loadOfficialWebBanners() async {
    final banners = await fetchOfficialHomeBanners();
    if (!mounted || banners.isEmpty) return;
    setState(() => _officialWebBanners = banners);
  }

  Future<void> _loadFromCache() async {
    if (_isCopySource) {
      final cached = await _repo.loadBFromCache();
      if (!mounted || cached == null || !_loading) return;
      setState(() {
        _copyHome = cached.home;
        _copyRecommendations = cached.home.recComics;
        _loading = false;
      });
      return;
    }
    final cached = await _repo.loadAFromCache();
    if (!mounted || cached == null || !_loading) return;
    setState(() {
      _home = cached.home;
      _rankingPreview = cached.ranking;
      _loading = false;
    });
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (_isCopySource) return _loadCopy(forceRefresh: forceRefresh);
    final hasData = _home != null;
    if (!hasData) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _refreshing = true);
    }
    try {
      final data = await _repo.loadA();
      if (!mounted) return;
      setState(() {
        _home = data.home;
        _rankingPreview = data.ranking;
        _loading = false;
        _refreshing = false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'home_page.load',
        ),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadCopy({bool forceRefresh = false}) async {
    final hasData = _copyHome != null;
    if (!hasData) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _refreshing = true);
    }
    try {
      final data = await _repo.loadB();
      var recommendations = data.home.recComics;
      try {
        final extra = await _api.manga.getCopyRecommendations(limit: 12);
        if (extra.list.isNotEmpty) recommendations = extra.list;
      } catch (e, stack) {
        unawaited(
          AppLogger.instance.recordWarning(
            e,
            stackTrace: stack,
            source: 'home_page.copy_recommendations',
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _copyHome = data.home;
        _copyRecommendations = recommendations;
        _loading = false;
        _refreshing = false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'home_page.load_copy',
        ),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e.toString();
      });
    }
  }

  void _openComic(Comic comic, String heroTagBase) {
    context.pushNamed(
      AppRoutes.comicDetail,
      pathParameters: {'pathWord': comic.pathWord},
      extra: ComicDetailExtra(initialComic: comic, heroTagBase: heroTagBase),
    );
  }

  void _openBannerItem(_MangaBannerItem item) {
    final comic = item.comic;
    if (comic != null) {
      _openComic(
        comic,
        ComicHeroTags.base(
          scope: 'home-banner',
          pathWord: comic.pathWord,
          index: 0,
        ),
      );
      return;
    }
    final pathWord = item.pathWord?.trim();
    if (pathWord != null && pathWord.isNotEmpty) {
      context.pushNamed(
        AppRoutes.comicDetail,
        pathParameters: {'pathWord': pathWord},
      );
    }
  }

  List<_MangaBannerItem> _bannerItems(List<MangaBanner> fallback) {
    if (_officialWebBanners.isNotEmpty) {
      return _officialWebBanners
          .take(5)
          .map(_MangaBannerItem.fromOfficial)
          .toList();
    }
    return fallback
        .map(_MangaBannerItem.fromBanner)
        .where((item) => item.cover.isNotEmpty)
        .take(5)
        .toList();
  }

  List<Widget> _buildFixedComicSection({
    required String title,
    required IconData icon,
    required List<Comic> items,
    required double hp,
    required String scope,
    VoidCallback? onMore,
    int maxItems = 12,
  }) {
    final visible = items.take(maxItems).toList(growable: false);
    if (visible.isEmpty) return const [];
    return [
      _SectionTitle(title: title, icon: icon, hp: hp, onMore: onMore),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(hp, 0, hp, 18),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final cardExtent = _mangaHomeCardMaxExtent(
              constraints.crossAxisExtent,
            );
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: cardExtent,
                childAspectRatio: _mangaHomeCardAspectRatio,
                mainAxisSpacing: _mangaHomeCardSpacing,
                crossAxisSpacing: _mangaHomeCardSpacing,
              ),
              delegate: SliverChildBuilderDelegate((_, i) {
                final comic = visible[i];
                final heroTagBase = ComicHeroTags.base(
                  scope: scope,
                  pathWord: comic.pathWord,
                  index: i,
                );
                return ComicCard(
                  comic: comic,
                  heroTagBase: heroTagBase,
                  onTap: () => _openComic(comic, heroTagBase),
                );
              }, childCount: visible.length),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildTopicSection(List<MangaTopic> topics, double hp) {
    final visible = topics
        .where((topic) => topic.cover.isNotEmpty)
        .take(4)
        .toList(growable: false);
    if (visible.isEmpty) return const [];
    return [
      _SectionTitle(
        title: '專題',
        icon: Icons.collections_bookmark_outlined,
        hp: hp,
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(hp, 0, hp, 18),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 520,
            childAspectRatio: 3.6,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate((context, i) {
            final topic = visible[i];
            return ComicCardSurface(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: topic.cover,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const CoverPlaceholder(),
                    errorWidget: (_, _, _) => const CoverPlaceholder.error(),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 10,
                    child: Text(
                      topic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }, childCount: visible.length),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const hp = 16.0;
    final home = _home;
    final copyHome = _copyHome;
    final isCopy = _isCopySource;

    if (_loading) {
      return Scaffold(
        floatingActionButton: _buildSourceFab(),
        body: const Center(child: ExpressiveLoadingIndicator()),
      );
    }

    final hasData = isCopy ? copyHome != null : home != null;
    if (_error != null && !hasData) {
      return Scaffold(
        floatingActionButton: _buildSourceFab(),
        body: ErrorRetryView(onRetry: _load),
      );
    }

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: SizedBox(height: MediaQuery.of(context).padding.top),
      ),
      if (_refreshing)
        const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
    ];

    if (isCopy && copyHome != null) {
      slivers.addAll(_buildCopySlivers(copyHome, hp));
    } else if (home != null) {
      final banners = _bannerItems(home.banners);
      if (_user.bannerVisible && banners.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: _MangaBannerCarousel(
                items: banners,
                hp: 0,
                onTap: _openBannerItem,
              ),
            ),
          ),
        );
      }

      final l10n = AppLocalizations.of(context)!;
      slivers.addAll(
        _buildFixedComicSection(
          title: l10n.hotRecommend,
          icon: Icons.auto_awesome,
          items: home.recommendations,
          hp: hp,
          scope: 'home-recommend',
          onMore: () => context.pushNamed(AppRoutes.recommend),
        ),
      );
      slivers.addAll(
        _buildFixedComicSection(
          title: l10n.comicRanking,
          icon: Icons.leaderboard,
          items: _rankingPreview,
          hp: hp,
          scope: 'home-ranking',
          onMore: () => context.pushNamed(AppRoutes.ranking),
        ),
      );
    }

    slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 88)));

    return Scaffold(
      floatingActionButton: _buildSourceFab(),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load(forceRefresh: true);
          await _loadOfficialWebBanners();
        },
        child: CustomScrollView(slivers: slivers),
      ),
    );
  }

  Widget _buildSourceFab() {
    final isCopy = _isCopySource;
    return FloatingActionButton.extended(
      heroTag: 'home-source-switch',
      tooltip: isCopy
          ? AppLocalizations.of(context)!.switchToHotHome
          : AppLocalizations.of(context)!.switchToCopyHome,
      onPressed: () => _user.setMangaHomeSource(isCopy ? 'hot' : 'copy'),
      icon: const Icon(Icons.swap_horiz, size: 20),
      label: Text(
        isCopy
            ? AppLocalizations.of(context)!.homeSourceCopy
            : AppLocalizations.of(context)!.homeSourceHot,
        style: AppTypography.fabLabel(Theme.of(context).textTheme),
      ),
    );
  }

  /// COPY 首页各板块
  /// COPY ???????????? + ??/??/???/??/???
  List<Widget> _buildCopySlivers(CopyMangaHome home, double hp) {
    final l10n = AppLocalizations.of(context)!;
    final slivers = <Widget>[];

    final banners = _bannerItems(home.banners);
    if (_user.bannerVisible && banners.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: _MangaBannerCarousel(
              items: banners,
              hp: 0,
              onTap: _openBannerItem,
            ),
          ),
        ),
      );
    }

    slivers.addAll(
      _buildFixedComicSection(
        title: l10n.copyRecommend,
        icon: Icons.auto_awesome,
        items: _copyRecommendations.isNotEmpty
            ? _copyRecommendations
            : home.recComics,
        hp: hp,
        scope: 'copy-recommend',
        onMore: () => context.pushNamed(
          AppRoutes.copyMangaList,
          pathParameters: {'kind': 'recommendations'},
        ),
      ),
    );
    slivers.addAll(
      _buildFixedComicSection(
        title: l10n.copyHotUpdate,
        icon: Icons.local_fire_department,
        items: home.hotComics,
        hp: hp,
        scope: 'copy-hot',
      ),
    );
    slivers.addAll(
      _buildFixedComicSection(
        title: l10n.copyNewArrival,
        icon: Icons.fiber_new,
        items: home.newComics,
        hp: hp,
        scope: 'copy-new',
        onMore: () => context.pushNamed(
          AppRoutes.copyMangaList,
          pathParameters: {'kind': 'newest'},
        ),
      ),
    );

    final seenTopics = <String>{};
    final topics = <MangaTopic>[...home.topics, ...home.topicsList].where((
      topic,
    ) {
      final key = topic.pathWord.isNotEmpty ? topic.pathWord : topic.cover;
      return key.isNotEmpty && seenTopics.add(key);
    }).toList();
    slivers.addAll(_buildTopicSection(topics, hp));

    slivers.addAll(
      _buildFixedComicSection(
        title: l10n.copyRanking,
        icon: Icons.leaderboard,
        items: home.rankDayComics,
        hp: hp,
        scope: 'copy-ranking',
        onMore: () => context.pushNamed(
          AppRoutes.copyMangaList,
          pathParameters: {'kind': 'ranking'},
        ),
      ),
    );

    return slivers;
  }
}
