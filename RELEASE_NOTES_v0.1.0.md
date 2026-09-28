# Kira Tablet v0.1.2 Preview

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
