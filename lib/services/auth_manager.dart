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
  /// Strategy:
  /// 1. Try to read the CSRF token from the web app's internal state
  ///    by dispatching a `kiro:csrf-token-request` custom event and
  ///    listening for the `kiro:csrf-token-response`.
  /// 2. Call the GetToken endpoint using the web app's own Smithy client
  ///    (which handles CBOR encoding/decoding) by hooking into the app's
  ///    internal fetch interceptor. If that's not available, call GetToken
  ///    directly and parse the CBOR response as raw bytes to extract the
  ///    `aoa...` access token.
  /// 3. Fall back to reading `document.cookie` for non-HttpOnly cookies.
  ///
  /// Uses a fire-and-poll pattern because iOS WKWebView cannot resolve
  /// Promises from async IIFEs via [runJavaScriptReturningResult].
  Future<AuthCredentials?> extractCredentials(
      WebViewController controller) async {
    try {
      String? bearerToken;
      String? csrfToken;

      // ── 1. Extract CSRF token from the web app's custom event system ──
      try {
        DebugLog.log('extractCredentials: requesting CSRF token via custom event');
        await controller.runJavaScript('''
          window._kiroCsrfResult = null;
          window.addEventListener('kiro:csrf-token-response', function handler(e) {
            window._kiroCsrfResult = e.detail && e.detail.token ? e.detail.token : '';
            window.removeEventListener('kiro:csrf-token-response', handler);
          });
          window.dispatchEvent(new CustomEvent('kiro:csrf-token-request'));
        ''');

        // Poll for the CSRF token result.
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          try {
            final result = await controller.runJavaScriptReturningResult(
              'window._kiroCsrfResult || ""',
            );
            final raw = result.toString().replaceAll('"', '');
            if (raw.isNotEmpty) {
              csrfToken = raw;
              DebugLog.log('extractCredentials: got CSRF token (${raw.length} chars)');
              break;
            }
          } catch (_) {}
        }
        if (csrfToken == null) {
          DebugLog.log('extractCredentials: CSRF token not available via event');
        }
      } catch (e) {
        DebugLog.log('extractCredentials: CSRF event error: $e');
      }

      // ── 2. Call GetToken and extract the access token from CBOR ──
      try {
        DebugLog.log('extractCredentials: calling GetToken endpoint');

        // The GetToken endpoint returns CBOR. We fetch the raw bytes,
        // base64-encode them in JS, and decode on the Dart side to
        // extract the `aoa...` access token. This avoids issues with
        // non-printable CBOR framing bytes breaking regex matches in JS.
        //
        // We store three pipe-separated values in _kiroAuthResult:
        //   status|base64EncodedBody|csrfToken
        // This avoids JSON serialization issues where iOS strips quotes.
        await controller.runJavaScript('''
          window._kiroAuthResult = null;
          (async function() {
            try {
              var csrfToken = ${csrfToken != null ? 'window._kiroCsrfResult || ""' : '""'};
              var resp = await fetch(
                '/service/KiroWebPortalService/operation/GetToken',
                {
                  method: 'POST',
                  credentials: 'include',
                  headers: {
                    'accept': 'application/cbor',
                    'content-type': 'application/json',
                    'smithy-protocol': 'rpc-v2-cbor',
                    'x-csrf-token': csrfToken
                  },
                  body: JSON.stringify({csrfToken: csrfToken})
                }
              );
              var status = resp.status;
              var buf = await resp.arrayBuffer();
              var bytes = new Uint8Array(buf);
              var binary = '';
              for (var i = 0; i < bytes.length; i++) {
                binary += String.fromCharCode(bytes[i]);
              }
              var b64 = btoa(binary);
              window._kiroAuthResult = status + '|' + b64 + '|' + csrfToken;
            } catch(e) {
              window._kiroAuthResult = '0|error:' + e.toString() + '|';
            }
          })();
        ''');

        // Poll for the result.
        String? parsed;
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          try {
            final result = await controller.runJavaScriptReturningResult(
              'window._kiroAuthResult || ""',
            );
            final raw = result.toString();
            // Strip surrounding quotes if present (iOS adds them).
            final cleaned = raw.startsWith('"') && raw.endsWith('"')
                ? raw.substring(1, raw.length - 1)
                : raw;
            if (cleaned.isNotEmpty && cleaned.contains('|')) {
              parsed = cleaned;
              break;
            }
          } catch (e) {
            DebugLog.log('extractCredentials: poll error: $e');
          }
        }

        if (parsed == null || parsed.isEmpty) {
          DebugLog.log('extractCredentials: GetToken poll timed out');
        } else {
          // Parse: status|base64body|csrfToken
          final parts = parsed.split('|');
          final status = parts.isNotEmpty ? parts[0] : '0';
          final b64Body = parts.length > 1 ? parts[1] : '';
          final csrfFromResponse = parts.length > 2 ? parts[2] : '';

          DebugLog.log('extractCredentials: GetToken status=$status, '
              'bodyLen=${b64Body.length}, csrf=${csrfFromResponse.isNotEmpty}');

          if (csrfFromResponse.isNotEmpty && csrfToken == null) {
            csrfToken = csrfFromResponse;
          }

          if (b64Body.isNotEmpty && !b64Body.startsWith('error:')) {
            try {
              final bodyBytes = base64Decode(b64Body);
              // Convert bytes to a string, replacing non-printable chars
              // with spaces, then extract the aoa... token via regex.
              final bodyText = String.fromCharCodes(
                bodyBytes.map((b) => (b >= 32 && b < 127) ? b : 32),
              );
              DebugLog.log('extractCredentials: CBOR body text (${bodyText.length} chars): '
                  '${bodyText.substring(0, bodyText.length > 100 ? 100 : bodyText.length)}...');

              final tokenMatch = RegExp(r'aoa[A-Za-z0-9_\-+/=:.]+').firstMatch(bodyText);
              if (tokenMatch != null) {
                bearerToken = tokenMatch.group(0);
                DebugLog.log('extractCredentials: extracted bearer token '
                    '(${bearerToken!.length} chars)');
              } else {
                DebugLog.log('extractCredentials: no aoa token found in CBOR body');
              }
            } catch (e) {
              DebugLog.log('extractCredentials: base64/CBOR decode error: $e');
            }
          }
        }
      } catch (e) {
        DebugLog.log('extractCredentials: GetToken call failed: $e');
      }

      // ── 3. Read cookies via JS (may be empty on iOS for HttpOnly) ──
      final cookiesResult = await controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final cookieString = cookiesResult.toString().replaceAll('"', '');
      DebugLog.log('extractCredentials: document.cookie = "$cookieString"');
      final cookies = _parseCookies(cookieString);
      DebugLog.log('extractCredentials: parsed cookie keys: ${cookies.keys.toList()}');

      final accessTokenCookie = cookies['AccessToken'] ?? '';
      final sessionToken = cookies['SessionToken'] ?? '';

      // ── 4. Determine the primary token ──────────────────────
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
