# Kira Tablet v0.1.6 Preview

First public preview focused on Windows 11 tablets and touch-first landscape use.

## Highlights
- Windows-first 1280×720 landscape startup.
- Native borderless fullscreen with touch-accessible exit controls.
- Touch-first reader and navigation; keyboard shortcuts are optional.
- Responsive layouts for small windows and Windows DPI scaling.
- High-resolution official-site banner carousel with proportional scaling.
- Fixed desktop-style Copy home sections instead of mobile-style sparse previews.
- Copy recommendations expanded to a 12-item desktop grid.
- Copy direct username/password login removed; official web login and token login remain.

## Known limitations
- Preview build; not code-signed.
- Web/API changes can temporarily break banner or data loading.
- Windows updater is intentionally disabled for this Preview; GitHub Releases is the update source of truth.

## v0.1.1 fixes
- COPY web login now opens the official www.mangacopy.com login page first.
- Uses a desktop Edge user agent on Windows WebView2.
- Reads session cookies from the active WebView profile after login.
- Falls back to the configured COPY mirror only when the official web page fails to load.

## v0.1.2 fixes
- Properly initializes WebViewEnvironment on Windows before creating InAppWebView.
- Stores WebView2 user data in the app support directory so installed builds can create a writable profile.
- Uses the same Windows WebViewEnvironment for cookie access.
- Shows an explicit WebView2 initialization state/error instead of a blank login pane.

## v0.1.3 fixes
- COPY token login now fetches the authenticated profile from /api/v3/member/info.
- Valid tokens no longer fail merely because no prior local COPY identity exists.
- Token validation remains side-effect free until the login is committed.

## v0.1.4 fixes
- Bookshelf update badges now reconcile server browse progress with local reading history.
- Reading the current latest chapter locally clears stale "updated" badges even if server browse data lags behind.
- Matching latest chapter names also count as caught up when COPY reissues a chapter UUID.
- "By update" now prioritizes comics with real unread updates, then sorts each group by official update time newest first.
- "By update" loads the full bookshelf before sorting so unread updates beyond the first page are not hidden.

## v0.1.5 fixes
- COPY chapter replacements now count as updates whenever the latest chapter UUID changes, even if the visible chapter name is unchanged.
- Windows login no longer rebuilds the whole page on every username keystroke.
- Token login no longer requests focus during dialog creation, reducing Windows 11 touch-keyboard focus churn.
- Login bottom controls no longer apply the touch-keyboard inset twice.
- GitHub Actions release workflow replaced with Windows-only CI; normal release tags no longer trigger inherited Android signing jobs or the obsolete kira.exe packaging check.
- Windows CI now gates analyzer, bookshelf update tests, login focus stability, COPY token profile resolution, and a real Windows release build.

## v0.1.6 fixes
- Bookshelf updates now include any newly uploaded content, including extras and alternate groups.
- Strict checks use the newest actual upload timestamp across all comic groups.
- Corrected or re-uploaded older-numbered chapters still count as updates when they receive a new UUID and newer upload time.
- Cross-group upload results are cached by the comic update marker so unchanged books do not repeat the extra checks.
- Reading the newest actual upload clears the update flag using merged server and local read state.
