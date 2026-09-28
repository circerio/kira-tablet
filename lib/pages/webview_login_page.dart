import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../api/user/user_api.dart';
import '../l10n/app_localizations.dart';
import '../models/copy_account_store.dart';
import '../providers/app_providers.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/copy_web_login.dart';
import '../utils/toast.dart';

/// 通过应用内 WebView 登录拷贝官网：用户在网页中完成登录后，
/// 从 cookie 中提取 token 并走令牌登录流程。
class WebViewLoginPage extends ConsumerStatefulWidget {
  const WebViewLoginPage({super.key});

  @override
  ConsumerState<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends ConsumerState<WebViewLoginPage> {
  InAppWebViewController? _controller;
  WebViewEnvironment? _webViewEnvironment;
  double _progress = 0;
  bool _completing = false;
  bool _readingCredentials = false;
  bool _usingFallback = false;
  bool _webViewReady = !Platform.isWindows;
  String? _webViewInitError;
  String? _error;

  static const _officialWebHost = 'www.mangacopy.com';

  String get _fallbackHost => ref.read(userManagerProvider).copyLoginHost;

  WebUri get _baseUri => WebUri('https://$_officialWebHost');

  WebUri get _loginUri =>
      WebUri('https://$_officialWebHost/web/login/loginByAccount');

  WebUri get _fallbackLoginUri =>
      WebUri('https://$_fallbackHost/web/login/loginByAccount');

  CookieManager get _cookieManager {
    final environment = _webViewEnvironment;
    if (Platform.isWindows && environment != null) {
      return CookieManager.instance(webViewEnvironment: environment);
    }
    return CookieManager.instance();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initializeWebView());
  }

  Future<void> _initializeWebView() async {
    if (!Platform.isWindows) return;
    try {
      final availableVersion = await WebViewEnvironment.getAvailableVersion();
      if (availableVersion == null || availableVersion.isEmpty) {
        throw StateError('WebView2 Runtime is not available');
      }

      final supportDirectory = await getApplicationSupportDirectory();
      final webViewDataDirectory = Directory(
        '${supportDirectory.path}${Platform.pathSeparator}webview2',
      );
      await webViewDataDirectory.create(recursive: true);

      final environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: webViewDataDirectory.path,
        ),
      );

      if (!mounted) {
        await environment.dispose();
        return;
      }

      setState(() {
        _webViewEnvironment = environment;
        _webViewReady = true;
        _webViewInitError = null;
      });
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordError(
          error,
          stackTrace: stack,
          source: 'webview_login.initialize_windows',
        ),
      );
      if (!mounted) return;
      setState(() {
        _webViewReady = false;
        _webViewInitError = 'WebView2 初始化失敗：$error';
      });
    }
  }

  @override
  void dispose() {
    final environment = _webViewEnvironment;
    _webViewEnvironment = null;
    if (environment != null) {
      unawaited(environment.dispose());
    }
    super.dispose();
  }

  /// 读取多个候选域名下的 cookie（官网可能跳转到 www 子域，
  /// token 可能写在父域或当前实际页面域上）。
  Future<Map<String, String>> _readCookieMap() async {
    final manager = _cookieManager;
    final result = <String, String>{};
    final candidates = <WebUri>{
      _baseUri,
      WebUri('https://mangacopy.com'),
      WebUri('https://$_fallbackHost'),
      WebUri('https://www.$_fallbackHost'),
    };
    final currentUrl = await _controller?.getUrl();
    if (currentUrl != null && _isLoginHost(currentUrl.host)) {
      candidates.add(currentUrl);
    }

    for (final uri in candidates) {
      try {
        final cookies = await manager.getCookies(
          url: uri,
          webViewController: _controller,
        );
        for (final c in cookies) {
          if (c.name.isNotEmpty && !result.containsKey(c.name)) {
            result[c.name] = c.value?.toString() ?? '';
          }
        }
      } catch (_, st) {
        unawaited(
          AppLogger.instance.recordWarning(
            'Unable to read COPY WebView cookies',
            stackTrace: st,
            source: 'webview_login.read_cookies',
          ),
        );
      }
    }
    return result;
  }

  bool _isLoginHost(String host) {
    final normalized = host.toLowerCase();
    final fallbackBase = _fallbackHost.startsWith('www.')
        ? _fallbackHost.substring(4)
        : _fallbackHost;
    return normalized == 'mangacopy.com' ||
        normalized == 'www.mangacopy.com' ||
        normalized == fallbackBase ||
        normalized == 'www.$fallbackBase';
  }

  /// Read the official page's candidate token and profile together. Storage
  /// from a navigation to another website must never be submitted as COPY.
  Future<CopyWebCredentials?> _extractCredentialsFromWebStorage() async {
    final currentUrl = await _controller?.getUrl();
    if (currentUrl == null || !_isLoginHost(currentUrl.host)) return null;
    const source = '''
(function(){
  try {
    var ls = {};
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      ls[k] = localStorage.getItem(k);
    }
    var ss = {};
    for (var j = 0; j < sessionStorage.length; j++) {
      var k2 = sessionStorage.key(j);
      ss[k2] = sessionStorage.getItem(k2);
    }
    return JSON.stringify({cookie: document.cookie, ls: ls, ss: ss});
  } catch (e) { return 'error: ' + e; }
})()
''';
    try {
      final raw = await _controller?.evaluateJavascript(source: source);
      final json = raw?.toString();
      if (json == null || json.isEmpty) return null;
      return parseCopyWebStorage(jsonDecode(json));
    } catch (_, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          'Unable to read COPY WebView storage',
          stackTrace: st,
          source: 'webview_login.web_storage',
        ),
      );
      return null;
    }
  }

  Future<void> _tryExtractAndFinish({bool manual = false}) async {
    if (_completing || _readingCredentials) return;
    final l10n = AppLocalizations.of(context)!;

    _readingCredentials = true;
    CopyWebCredentials? credentials;
    try {
      credentials = parseCopyWebCookies(await _readCookieMap());
      if (credentials == null ||
          (credentials.userId.isEmpty && credentials.username.isEmpty)) {
        final stored = await _extractCredentialsFromWebStorage();
        if (credentials == null) {
          credentials = stored;
        } else if (stored?.token == credentials.token) {
          credentials = stored;
        }
      }
    } catch (_, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          'Unable to read COPY WebView credentials',
          stackTrace: st,
          source: 'webview_login.read_credentials',
        ),
      );
    } finally {
      _readingCredentials = false;
    }
    if (!mounted) return;
    if (credentials == null) {
      if (manual) showToast(context, l10n.profileWebLoginNotDetected);
      return;
    }

    setState(() {
      _completing = true;
      _error = null;
    });

    final user = ref.read(userManagerProvider);
    final api = ref.read(userApiProvider);
    try {
      final saved = await completeCopyWebLogin(
        user: user,
        api: api,
        credentials: credentials,
      );
      if (!mounted) return;
      if (saved) {
        context.pop(true);
      } else {
        setState(() {
          _completing = false;
          _error = l10n.copyAccountLoginSuperseded;
        });
      }
    } catch (error) {
      unawaited(
        AppLogger.instance.recordWarning(
          'COPY WebView login failed',
          source: 'webview_login.validate',
        ),
      );
      if (mounted) {
        setState(() {
          _completing = false;
          _error = error is CopyProfileUnavailableException
              ? l10n.copyProfileRefreshUnavailable
              : error is CopyAccountStorageException
              ? l10n.copyAccountStorageFailed
              : l10n.profileWebLoginFailed;
        });
      }
    }
  }

  Future<void> _handleWebError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) async {
    if (request.isForMainFrame != true || _usingFallback) return;
    final host = request.url.host.toLowerCase();
    if (host != 'mangacopy.com' && host != 'www.mangacopy.com') return;

    _usingFallback = true;
    if (mounted) {
      setState(() {
        _error = '官網主站載入失敗，正在切換官方備援入口…';
      });
    }
    await controller.loadUrl(urlRequest: URLRequest(url: _fallbackLoginUri));
  }

  Future<void> _resetWebSession() async {
    final manager = _cookieManager;
    await manager.deleteCookies(url: _baseUri, domain: '.mangacopy.com');
    await manager.deleteCookies(url: _baseUri, domain: 'mangacopy.com');
    final fallbackBase = WebUri('https://$_fallbackHost');
    await manager.deleteCookies(url: fallbackBase, domain: '.$_fallbackHost');
    await manager.deleteCookies(url: fallbackBase, domain: _fallbackHost);
    _usingFallback = false;
    await _controller?.loadUrl(urlRequest: URLRequest(url: _loginUri));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileWebLoginPageTitle),
        actions: [
          IconButton(
            tooltip: l10n.profileWebLoginResetTooltip,
            onPressed: _completing ? null : _resetWebSession,
            icon: const Icon(Icons.restart_alt),
          ),
          TextButton(
            onPressed: _completing
                ? null
                : () => _tryExtractAndFinish(manual: true),
            child: Text(l10n.profileWebLoginManualButton),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_progress < 1)
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                ),
              Container(
                width: double.infinity,
                color: cs.surfaceBright,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  l10n.profileWebLoginHint,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              if (_error != null)
                Container(
                  width: double.infinity,
                  color: cs.errorContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    _error!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
                  ),
                ),
              Expanded(
                child: _webViewReady
                    ? InAppWebView(
                        webViewEnvironment: _webViewEnvironment,
                        initialUrlRequest: URLRequest(url: _loginUri),
                        initialSettings: InAppWebViewSettings(
                          userAgent:
                              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                              'AppleWebKit/537.36 (KHTML, like Gecko) '
                              'Chrome/154.0.0.0 Safari/537.36 Edg/154.0.0.0',
                        ),
                        onWebViewCreated: (controller) =>
                            _controller = controller,
                        onProgressChanged: (controller, progress) {
                          setState(() => _progress = progress / 100);
                        },
                        onLoadStop: (controller, url) {
                          if (mounted && _error != null && !_completing) {
                            setState(() => _error = null);
                          }
                          unawaited(_tryExtractAndFinish());
                        },
                        onReceivedError: _handleWebError,
                        onUpdateVisitedHistory: (controller, url, isReload) =>
                            _tryExtractAndFinish(),
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xxl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_webViewInitError == null)
                                const CircularProgressIndicator()
                              else
                                Icon(
                                  Icons.web_asset_off,
                                  size: 48,
                                  color: cs.error,
                                ),
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                _webViewInitError ?? '????? WebView2?',
                                textAlign: TextAlign.center,
                              ),
                              if (_webViewInitError != null) ...[
                                const SizedBox(height: AppSpacing.lg),
                                FilledButton.icon(
                                  onPressed: () {
                                    setState(() => _webViewInitError = null);
                                    unawaited(_initializeWebView());
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('??'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
          if (_completing)
            Positioned.fill(
              child: ColoredBox(
                color: cs.scrim.withValues(alpha: 0.4),
                child: Center(
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: AppSpacing.lg),
                          Text(l10n.profileWebLoginCompleting),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
