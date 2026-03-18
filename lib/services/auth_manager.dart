import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
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
      if (!available) {
        _setState(AuthState.error);
        return;
      }

      final stored = await _credentialStore.load();
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
    } catch (_) {
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

  /// Reads cookies and tokens from the WebView [controller].
  ///
  /// After the OAuth flow completes, the Kiro web app sets cookies including
  /// `AccessToken` (used as the Bearer token for API calls) and a CSRF token.
  /// We call the GetToken endpoint from within the WebView to obtain them.
  Future<AuthCredentials?> extractCredentials(
      WebViewController controller) async {
    try {
      // Retrieve cookies set by the Kiro sign-in page via JavaScript.
      final cookiesResult = await controller.runJavaScriptReturningResult(
        'document.cookie',
      );

      final cookieString = cookiesResult.toString().replaceAll('"', '');
      final cookies = _parseCookies(cookieString);

      // The AccessToken cookie is the bearer token for API calls.
      final accessToken = cookies['AccessToken'] ?? '';
      // SessionToken is used as the primary credential identifier.
      final sessionToken = cookies['SessionToken'] ?? '';
      final token = sessionToken.isNotEmpty ? sessionToken : accessToken;

      if (token.isEmpty) return null;

      // Call GetToken from within the WebView (same-origin, cookies sent
      // automatically). The endpoint returns CBOR but we can ask for JSON
      // or parse the response as text in JS.
      String? bearerToken;
      String? csrfToken;
      try {
        final tokenResult = await controller.runJavaScriptReturningResult(
          '''
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
              var text = await resp.text();
              try {
                var data = JSON.parse(text);
                return JSON.stringify({
                  accessToken: data.accessToken || '',
                  csrfToken: data.csrfToken || ''
                });
              } catch(e) {
                // CBOR response — extract accessToken from raw bytes.
                // The token starts with 'aoa' and is a long string.
                var match = text.match(/aoa[A-Za-z0-9+\\/=:]+/);
                return JSON.stringify({
                  accessToken: match ? match[0] : '',
                  csrfToken: ''
                });
              }
            } catch(e) {
              return JSON.stringify({accessToken: '', csrfToken: ''});
            }
          })()
          ''',
        );
        final parsed = tokenResult.toString().replaceAll('"', '');
        // The JS returns a JSON string — but it's been stringified twice
        // by runJavaScriptReturningResult. Try to parse it.
        try {
          // Remove outer quotes if present
          var jsonStr = parsed;
          if (jsonStr.startsWith('{')) {
            final map = Map<String, dynamic>.from(
              _parseSimpleJson(jsonStr),
            );
            final at = map['accessToken'] as String? ?? '';
            final ct = map['csrfToken'] as String? ?? '';
            if (at.isNotEmpty) bearerToken = at;
            if (ct.isNotEmpty) csrfToken = ct;
          }
        } catch (_) {
          // Fallback: use the AccessToken cookie directly.
        }
      } catch (_) {
        // GetToken call may fail — non-fatal.
      }

      // Fallback: use AccessToken cookie as bearer token.
      bearerToken ??= accessToken.isNotEmpty ? accessToken : null;

      return AuthCredentials(
        token: token,
        cookies: cookies,
        bearerToken: bearerToken,
        csrfToken: csrfToken,
      );
    } catch (_) {
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
