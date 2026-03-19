import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;

import 'debug_log.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/auth_credentials.dart';
import '../models/auth_state.dart';
import 'credential_store.dart';

/// Central component managing the authentication lifecycle.
///
/// Uses [ChangeNotifier] for compatibility with [Provider] and exposes
/// a [Stream<AuthState>] for reactive UI updates.
class AuthManager extends ChangeNotifier {
  AuthManager({required CredentialStore credentialStore})
      : _credentialStore = credentialStore;

  final CredentialStore _credentialStore;

  final StreamController<AuthState> _stateController =
      StreamController<AuthState>.broadcast();

  AuthState _state = AuthState.unknown;
  AuthCredentials? _credentials;

  /// The current authentication state.
  AuthState get state => _state;

  /// A broadcast stream of authentication state changes.
  Stream<AuthState> get stateStream => _stateController.stream;

  /// The current stored credentials, if any.
  AuthCredentials? get credentials => _credentials;

  /// Loads credentials from the [CredentialStore], validates them,
  /// and sets the state to [AuthState.authenticated] or
  /// [AuthState.unauthenticated] accordingly.
  ///
  /// If the store is unavailable, transitions to [AuthState.error].
  Future<void> initialize() async {
    try {
      final available = await _credentialStore.isAvailable;
      DebugLog.log('initialize: credentialStore.isAvailable=$available');
      if (!available) {
        _setState(AuthState.error);
        return;
      }

      final stored = await _credentialStore.load();
      DebugLog.log('initialize: stored=${stored != null}, isValid=${stored?.isValid}');
      if (stored != null && stored.isValid) {
        _credentials = stored;
        _setState(AuthState.authenticated);
      } else {
        _credentials = null;
        if (stored != null) {
          await _credentialStore.clear();
        }
        _setState(AuthState.unauthenticated);
      }
    } catch (e) {
      DebugLog.log('initialize: caught exception: $e');
      _credentials = null;
      _setState(AuthState.error);
    }
  }

  /// Handles sign-in completion on web by reading cookies from the
  /// browser document directly (no WebViewController needed).
  Future<void> handleWebSignInComplete() async {
    try {
      final extracted = await _extractWebCredentials();
      if (extracted == null || !extracted.isValid) {
        _setState(AuthState.error);
        return;
      }

      await _credentialStore.save(extracted);
      _credentials = extracted;
      _setState(AuthState.authenticated);
    } catch (_) {
      _setState(AuthState.error);
    }
  }

  /// Handles web sign-in with explicitly provided tokens.
  ///
  /// Called when the user provides their bearer token (and optionally CSRF
  /// token) after completing the OAuth flow in a popup window.
  Future<void> handleWebSignInWithTokens({
    required String bearerToken,
    String? csrfToken,
  }) async {
    try {
      final credentials = AuthCredentials(
        token: bearerToken,
        cookies: const {},
        bearerToken: bearerToken,
        csrfToken: csrfToken,
      );

      if (!credentials.isValid) {
        _setState(AuthState.error);
        return;
      }

      await _credentialStore.save(credentials);
      _credentials = credentials;
      _setState(AuthState.authenticated);
    } catch (_) {
      _setState(AuthState.error);
    }
  }

  /// Reads auth credentials from browser cookies and localStorage (web platform only).
  Future<AuthCredentials?> _extractWebCredentials() async {
    try {
      // On web, after the OAuth popup completes, the user is authenticated
      // on app.kiro.dev via cookies. Since our Flutter app runs on a
      // different origin, we can't directly access those cookies or tokens.
      // We mark as authenticated and the web content view will redirect
      // to app.kiro.dev where the session is active.
      return AuthCredentials(
        token: 'web-session',
        cookies: const {},
      );
    } catch (_) {
      return null;
    }
  }

  /// Extracts credentials from the WebView [controller] after a
  /// successful sign-in, saves them to the store, and transitions
  /// to [AuthState.authenticated].
  ///
  /// If extraction fails (null credentials), transitions to
  /// [AuthState.error].
  Future<void> handleSignInComplete(WebViewController controller) async {
    try {
      final extracted = await extractCredentials(controller);
      DebugLog.log('[AuthManager] handleSignInComplete: extracted=${extracted != null}, isValid=${extracted?.isValid}');
      if (extracted == null || !extracted.isValid) {
        DebugLog.log('[AuthManager] handleSignInComplete: transitioning to error state');
        _setState(AuthState.error);
        return;
      }

      await _credentialStore.save(extracted);
      _credentials = extracted;
      _setState(AuthState.authenticated);
    } catch (e) {
      DebugLog.log('handleSignInComplete: caught exception: $e');
      _setState(AuthState.error);
    }
  }

  /// Reads cookies and tokens from the WebView [controller].
  ///
  /// Strategy: first call the GetToken endpoint from within the WebView
  /// (same-origin, so cookies are sent automatically even if HttpOnly).
  /// If that succeeds we have everything we need. Only fall back to
  /// reading `document.cookie` via JS if GetToken fails.
  ///
  /// Uses a fire-and-poll pattern instead of [runJavaScriptReturningResult]
  /// for the async GetToken call because iOS WKWebView cannot resolve
  /// Promises returned by async IIFEs — it throws
  /// `FWFEvaluateJavaScriptError`. The async JS stores its result in a
  /// global variable (`window._kiroAuthResult`) which we then poll for
  /// synchronously.
  Future<AuthCredentials?> extractCredentials(
      WebViewController controller) async {
    try {
      // ── 1. Try GetToken endpoint via fire-and-poll (primary path) ──
      String? bearerToken;
      String? csrfToken;
      try {
        DebugLog.log('extractCredentials: calling GetToken endpoint');

        // Clear any previous result and kick off the async fetch.
        // runJavaScript is fire-and-forget — no Promise resolution needed.
        await controller.runJavaScript(
          '''
          window._kiroAuthResult = null;
          (async function() {
            try {
              var resp = await fetch(
                '/service/KiroWebPortalService/operation/GetToken',
                {
                  method: 'POST',
                  credentials: 'include',
                  headers: {
                    'accept': 'application/json',
                    'content-type': 'application/json'
                  },
                  body: JSON.stringify({})
                }
              );
              var status = resp.status;
              var text = await resp.text();
              try {
                var data = JSON.parse(text);
                window._kiroAuthResult = JSON.stringify({
                  status: status,
                  accessToken: data.accessToken || '',
                  csrfToken: data.csrfToken || ''
                });
              } catch(e) {
                var match = text.match(/aoa[A-Za-z0-9+\\\\/=:]+/);
                window._kiroAuthResult = JSON.stringify({
                  status: status,
                  accessToken: match ? match[0] : '',
                  csrfToken: '',
                  parseError: e.toString()
                });
              }
            } catch(e) {
              window._kiroAuthResult = JSON.stringify({
                status: 0, accessToken: '', csrfToken: '',
                fetchError: e.toString()
              });
            }
          })();
          ''',
        );

        // Poll for the result — the fetch typically completes in <2s.
        String? parsed;
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          try {
            final result = await controller.runJavaScriptReturningResult(
              'window._kiroAuthResult || ""',
            );
            final raw = result.toString().replaceAll('"', '');
            if (raw.isNotEmpty) {
              parsed = raw;
              break;
            }
          } catch (e) {
            DebugLog.log('extractCredentials: poll error: $e');
          }
        }

        if (parsed == null || parsed.isEmpty) {
          DebugLog.log('extractCredentials: GetToken poll timed out');
        } else {
          DebugLog.log('extractCredentials: GetToken raw result: $parsed');
          try {
            if (parsed.startsWith('{')) {
              final map = Map<String, dynamic>.from(_parseSimpleJson(parsed));
              final at = map['accessToken'] as String? ?? '';
              final ct = map['csrfToken'] as String? ?? '';
              if (at.isNotEmpty) bearerToken = at;
              if (ct.isNotEmpty) csrfToken = ct;
              DebugLog.log('extractCredentials: GetToken status=${map['status']}, '
                  'accessToken=${at.isNotEmpty}, csrfToken=${ct.isNotEmpty}');
            }
          } catch (e) {
            DebugLog.log('extractCredentials: GetToken parse error: $e');
          }
        }
      } catch (e) {
        DebugLog.log('extractCredentials: GetToken call failed: $e');
      }

      // ── 2. Read cookies via JS (may be empty on iOS for HttpOnly) ──
      final cookiesResult = await controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final cookieString = cookiesResult.toString().replaceAll('"', '');
      DebugLog.log('extractCredentials: document.cookie = "$cookieString"');
      final cookies = _parseCookies(cookieString);
      DebugLog.log('extractCredentials: parsed cookie keys: ${cookies.keys.toList()}');

      final accessTokenCookie = cookies['AccessToken'] ?? '';
      final sessionToken = cookies['SessionToken'] ?? '';

      // ── 3. Determine the primary token ──────────────────────
      // Prefer the bearer token from GetToken, then SessionToken cookie,
      // then AccessToken cookie.
      final token = bearerToken ??
          (sessionToken.isNotEmpty ? sessionToken : null) ??
          (accessTokenCookie.isNotEmpty ? accessTokenCookie : null) ??
          '';

      DebugLog.log('extractCredentials: final token=${token.isNotEmpty}, '
          'bearerToken=${bearerToken != null}, csrfToken=${csrfToken != null}');

      if (token.isEmpty) {
        DebugLog.log('extractCredentials: no usable token found — '
            'both GetToken and cookie extraction failed');
        return null;
      }

      // Use bearer token from GetToken, or fall back to AccessToken cookie.
      bearerToken ??= accessTokenCookie.isNotEmpty ? accessTokenCookie : null;

      return AuthCredentials(
        token: token,
        cookies: cookies,
        bearerToken: bearerToken,
        csrfToken: csrfToken,
      );
    } catch (e) {
      DebugLog.log('extractCredentials: caught exception: $e');
      return null;
    }
  }

  /// Simple JSON parser for flat objects like {key: value, ...}.
  Map<String, dynamic> _parseSimpleJson(String json) {
    // Use dart:convert for proper parsing.
    try {
      return Map<String, dynamic>.from(
        (const JsonDecoder().convert(json)) as Map,
      );
    } catch (_) {
      return {};
    }
  }

  /// Validates the currently stored credentials by checking [isValid].
  ///
  /// If credentials are invalid or missing, clears the store and
  /// transitions to [AuthState.unauthenticated].
  Future<void> validateCredentials() async {
    if (_credentials != null && _credentials!.isValid) {
      _setState(AuthState.authenticated);
    } else {
      _credentials = null;
      await _credentialStore.clear();
      _setState(AuthState.unauthenticated);
    }
  }

  /// Clears the [CredentialStore], clears WebView data, and transitions
  /// to [AuthState.unauthenticated].
  Future<void> signOut() async {
    _credentials = null;
    await _credentialStore.clear();

    // Clear WebView cookies and cache (native platforms only).
    if (!kIsWeb) {
      try {
        final cookieManager = WebViewCookieManager();
        await cookieManager.clearCookies();
      } catch (_) {
        // WebView cookie clearing may fail on some platforms — non-fatal.
      }
    }

    _setState(AuthState.unauthenticated);
  }

  /// Clears credentials and transitions to [AuthState.unauthenticated].
  ///
  /// Called when an auth error (e.g. HTTP 401) is detected.
  Future<void> handleAuthError() async {
    _credentials = null;
    await _credentialStore.clear();
    _setState(AuthState.unauthenticated);
  }

  /// Parses a cookie string (e.g. "key1=val1; key2=val2") into a map.
  Map<String, String> _parseCookies(String cookieString) {
    final cookies = <String, String>{};
    if (cookieString.isEmpty) return cookies;

    for (final pair in cookieString.split(';')) {
      final trimmed = pair.trim();
      final equalsIndex = trimmed.indexOf('=');
      if (equalsIndex > 0) {
        final key = trimmed.substring(0, equalsIndex).trim();
        final value = trimmed.substring(equalsIndex + 1).trim();
        cookies[key] = value;
      }
    }
    return cookies;
  }

  void _setState(AuthState newState) {
    _state = newState;
    _stateController.add(newState);
    notifyListeners();
  }

  @override
  void dispose() {
    _stateController.close();
    super.dispose();
  }
}
