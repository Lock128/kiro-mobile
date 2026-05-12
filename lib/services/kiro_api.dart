import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutterrific_opentelemetry/flutterrific_opentelemetry.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/auth_credentials.dart';
import 'telemetry_service.dart';

/// Client for the Kiro Web Portal API.
///
/// The API moved from codewhisperer.us-east-1.amazonaws.com to
/// app.kiro.dev/service/KiroWebPortalService/operation/ using the
/// Smithy rpc-v2-cbor protocol. We use JSON content-type which the
/// service also accepts.
class KiroApi {
  KiroApi({
    required AuthCredentials credentials,
    http.Client? httpClient,
    TelemetryService? telemetryService,
  })  : _credentials = credentials,
        _client = httpClient ?? http.Client(),
        _telemetry = telemetryService;

  final AuthCredentials _credentials;
  final http.Client _client;
  final TelemetryService? _telemetry;

  static const _baseUrl = 'https://app.kiro.dev/service/KiroWebPortalService/operation';
  static const _profileArn =
      'arn:aws:codewhisperer:us-east-1:638616132270:profile/AAAACCCCXXXX';

  static const _uuid = Uuid();

  static String get _osLabel {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.windows:
        return 'Windows';
      default:
        return 'other';
    }
  }

  Map<String, String> get _headers => {
        'accept': 'application/json',
        'content-type': 'application/json',
        'smithy-protocol': 'rpc-v2-cbor',
        if (_credentials.csrfToken != null)
          'x-csrf-token': _credentials.csrfToken!,
        if (_credentials.userId != null)
          'x-kiro-userid': _credentials.userId!,
        'x-amz-user-agent':
            'aws-sdk-js/1.0.0 ua/2.1 os/$_osLabel lang/js api/bigweaver#1.0.0',
        'amz-sdk-invocation-id': _uuid.v4(),
        'amz-sdk-request': 'attempt=1; max=1',
      };

  /// Fetches user info after authentication.
  Future<UserInfo> getUserInfo() async {
    final span = _startSpan('kiro_api.get_user_info', 'POST', '$_baseUrl/GetUserInfo');
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/GetUserInfo'),
        headers: _headers,
        body: jsonEncode({'origin': 'KIRO_IDE'}),
      );
      _checkResponse(response, 'GetUserInfo');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      span?.setStatus(SpanStatusCode.Ok);
      return UserInfo.fromJson(data);
    } catch (e, st) {
      span?.recordException(e, stackTrace: st);
      span?.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span?.end();
    }
  }

  /// Lists all spaces (replaces the old listSessions + listAgentTasks).
  Future<List<Space>> listSpaces() async {
    final span = _startSpan('kiro_api.list_spaces', 'POST', '$_baseUrl/ListSpaces');
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/ListSpaces'),
        headers: _headers,
        body: jsonEncode({'profileArn': _profileArn}),
      );
      _checkResponse(response, 'ListSpaces');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final spaces = data['spaces'] as List? ?? [];
      span?.setStatus(SpanStatusCode.Ok);
      return spaces
          .map((e) => Space.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      span?.recordException(e, stackTrace: st);
      span?.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span?.end();
    }
  }

  /// Gets details of a specific space.
  Future<Space> getSpace({required String spaceId}) async {
    final span = _startSpan('kiro_api.get_space', 'POST', '$_baseUrl/GetSpace');
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/GetSpace'),
        headers: _headers,
        body: jsonEncode({
          'spaceId': spaceId,
          'profileArn': _profileArn,
        }),
      );
      _checkResponse(response, 'GetSpace');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      span?.setStatus(SpanStatusCode.Ok);
      return Space.fromJson(data);
    } catch (e, st) {
      span?.recordException(e, stackTrace: st);
      span?.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span?.end();
    }
  }

  /// Gets the main chat session for a space.
  Future<MainChatSession> getMainChatSession({required String spaceId}) async {
    final span = _startSpan('kiro_api.get_main_chat_session', 'POST', '$_baseUrl/GetMainChatSession');
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/GetMainChatSession'),
        headers: _headers,
        body: jsonEncode({
          'spaceId': spaceId,
          'profileArn': _profileArn,
        }),
      );
      _checkResponse(response, 'GetMainChatSession');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      span?.setStatus(SpanStatusCode.Ok);
      return MainChatSession.fromJson(data);
    } catch (e, st) {
      span?.recordException(e, stackTrace: st);
      span?.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span?.end();
    }
  }

  /// Creates a new space with the given repos. Returns the spaceId.
  Future<String> createSpace({
    required List<ProviderResource> repos,
    String spaceType = 'AUTONOMOUS',
  }) async {
    final span = _startSpan('kiro_api.create_space', 'POST', '$_baseUrl/CreateSpace');
    try {
      // The new API takes providerResources as a single object (not a list)
      // with providerType, name, and url.
      final providerResource = repos.isNotEmpty
          ? {
              'providerType': 'GITHUB',
              'name': repos.first.displayName,
              'url': repos.first.url ?? 'https://github.com/${repos.first.displayName}',
            }
          : null;

      final body = <String, dynamic>{
        'spaceType': spaceType,
        'profileArn': _profileArn,
        if (_credentials.csrfToken != null)
          'csrfToken': _credentials.csrfToken!,
      };
      if (providerResource != null) {
        body['providerResources'] = providerResource;
      }

      final response = await _client.post(
        Uri.parse('$_baseUrl/CreateSpace'),
        headers: _headers,
        body: jsonEncode(body),
      );
      _checkResponse(response, 'CreateSpace');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      span?.setStatus(SpanStatusCode.Ok);
      return data['spaceId'] as String;
    } catch (e, st) {
      span?.recordException(e, stackTrace: st);
      span?.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span?.end();
    }
  }

  /// Fetches session resources (messages/activities) for a space session.
  Future<SessionResources> getSessionResources({
    required String spaceId,
    required String sessionId,
  }) async {
    final span = _startSpan('kiro_api.get_session_resources', 'POST', '$_baseUrl/GetSessionResources');
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/GetSessionResources'),
        headers: _headers,
        body: jsonEncode({
          'spaceId': spaceId,
          'sessionId': sessionId,
          'profileArn': _profileArn,
        }),
      );
      _checkResponse(response, 'GetSessionResources');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      span?.setStatus(SpanStatusCode.Ok);
      return SessionResources.fromJson(data);
    } catch (e, st) {
      span?.recordException(e, stackTrace: st);
      span?.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span?.end();
    }
  }

  /// Sends a user message to a space session (streaming endpoint).
  /// Returns immediately — poll [getSessionResources] for updates.
  Future<void> streamSendMessage({
    required String spaceId,
    required String sessionId,
    required String message,
    String modelId = 'auto',
  }) async {
    final span = _startSpan('kiro_api.stream_send_message', 'POST', '$_baseUrl/StreamSendMessage');
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_baseUrl/StreamSendMessage'),
      );
      request.headers.addAll(_headers);
      request.body = jsonEncode({
        'spaceId': spaceId,
        'sessionId': sessionId,
        'contentBlocks': {
          'text': {'text': message},
        },
        'modelId': modelId,
        'profileArn': _profileArn,
        if (_credentials.csrfToken != null)
          'csrfToken': _credentials.csrfToken!,
      });

      final streamed = await _client.send(request);
      if (streamed.statusCode == 401 || streamed.statusCode == 403) {
        throw AuthExpiredException();
      }
      if (streamed.statusCode != 200) {
        throw ApiException(
            'StreamSendMessage failed: ${streamed.statusCode}');
      }
      // Drain the stream so the connection is released.
      await streamed.stream.drain<void>();
      span?.setStatus(SpanStatusCode.Ok);
    } catch (e, st) {
      span?.recordException(e, stackTrace: st);
      span?.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span?.end();
    }
  }

  /// Lists available provider resources (GitHub repos).
  Future<List<ProviderResource>> listProviderResources() async {
    final span = _startSpan('kiro_api.list_provider_resources', 'POST', '$_baseUrl/ListProviderResources');
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/ListProviderResources'),
        headers: _headers,
        body: jsonEncode({
          'providerType': 'GITHUB',
          'profileArn': _profileArn,
          if (_credentials.csrfToken != null)
            'csrfToken': _credentials.csrfToken!,
        }),
      );
      _checkResponse(response, 'ListProviderResources');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final resources = data['resources'] as List? ?? [];
      span?.setStatus(SpanStatusCode.Ok);
      return resources
          .map((r) => ProviderResource.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      span?.recordException(e, stackTrace: st);
      span?.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span?.end();
    }
  }

  /// Lists available providers (replaces ListConnections).
  Future<List<String>> listAvailableProviders() async {
    final span = _startSpan('kiro_api.list_available_providers', 'POST', '$_baseUrl/ListAvailableProviders');
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/ListAvailableProviders'),
        headers: _headers,
        body: jsonEncode({
          'profileArn': _profileArn,
          if (_credentials.csrfToken != null)
            'csrfToken': _credentials.csrfToken!,
        }),
      );
      _checkResponse(response, 'ListAvailableProviders');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final providers = data['providers'] as List? ?? [];
      span?.setStatus(SpanStatusCode.Ok);
      return providers.cast<String>();
    } catch (e, st) {
      span?.recordException(e, stackTrace: st);
      span?.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span?.end();
    }
  }

  /// Gets user usage and limits.
  Future<Map<String, dynamic>> getUserUsageAndLimits() async {
    final span = _startSpan('kiro_api.get_user_usage_and_limits', 'POST', '$_baseUrl/GetUserUsageAndLimits');
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/GetUserUsageAndLimits'),
        headers: _headers,
        body: jsonEncode({
          'profileArn': _profileArn,
          if (_credentials.csrfToken != null)
            'csrfToken': _credentials.csrfToken!,
        }),
      );
      _checkResponse(response, 'GetUserUsageAndLimits');
      span?.setStatus(SpanStatusCode.Ok);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e, st) {
      span?.recordException(e, stackTrace: st);
      span?.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span?.end();
    }
  }

  void _checkResponse(http.Response response, String operation) {
    if (response.statusCode == 401) throw AuthExpiredException();
    if (response.statusCode == 403) throw AuthExpiredException();
    if (response.statusCode != 200) {
      throw ApiException('$operation failed: ${response.statusCode}');
    }
  }

  /// Creates a trace span if telemetry is configured, or returns `null`.
  dynamic _startSpan(String name, String method, String url) {
    final tracer = _telemetry?.tracer;
    if (tracer == null) return null;
    return tracer.startSpan(
      name,
      kind: SpanKind.client,
      attributes: <String, Object>{
        'http.method': method,
        'http.url': url,
      }.toAttributes(),
    );
  }

  void dispose() => _client.close();
}

// ─── Models ──────────────────────────────────────────────────────────────────

/// User info returned by GetUserInfo.
class UserInfo {
  UserInfo({
    this.email,
    this.userId,
    this.status,
    this.featureFlags = const [],
  });

  final String? email;
  final String? userId;
  final String? status;
  final List<String> featureFlags;

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
        email: json['email'] as String?,
        userId: json['userId'] as String?,
        status: json['status'] as String?,
        featureFlags: (json['featureFlags'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}

/// A space (replaces the old ChatSession + AgentTask concepts).
class Space {
  Space({
    required this.spaceId,
    this.displayName,
    this.spaceType,
    this.status,
    this.role,
    this.createdAt,
    this.updatedAt,
    this.sessionIds = const [],
    this.providerResources,
    this.githubRepo,
  });

  final String spaceId;
  final String? displayName;
  final String? spaceType;
  final String? status;
  final String? role;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> sessionIds;
  final List<Map<String, dynamic>>? providerResources;
  final Map<String, dynamic>? githubRepo;

  /// Whether this is an autonomous (task) space.
  bool get isAutonomous => spaceType == 'AUTONOMOUS';

  /// Whether this is a vibe (chat) space.
  bool get isVibe => spaceType == 'VIBE';

  /// Human-readable display name.
  String get name {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    if (githubRepo != null) {
      final fullName = githubRepo!['fullName'] as String?;
      if (fullName != null && fullName.isNotEmpty) return fullName;
    }
    return 'Space ${spaceId.substring(0, 8)}…';
  }

  factory Space.fromJson(Map<String, dynamic> json) => Space(
        spaceId: json['spaceId'] as String? ?? '',
        displayName: json['displayName'] as String?,
        spaceType: json['spaceType'] as String?,
        status: json['status'] as String?,
        role: json['role'] as String?,
        createdAt: _tryParseTimestamp(json['createdAt']),
        updatedAt: _tryParseTimestamp(json['updatedAt']),
        sessionIds: (json['sessionIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        providerResources: (json['providerResources'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        githubRepo: json['githubRepo'] as Map<String, dynamic>?,
      );
}

/// Main chat session info for a space.
class MainChatSession {
  MainChatSession({
    required this.sessionId,
    this.hasMainChat = false,
  });

  final String sessionId;
  final bool hasMainChat;

  factory MainChatSession.fromJson(Map<String, dynamic> json) =>
      MainChatSession(
        sessionId: json['sessionId'] as String? ?? '',
        hasMainChat: json['hasMainChat'] as bool? ?? false,
      );
}

/// Session resources (messages/pull requests).
class SessionResources {
  SessionResources({
    this.pullRequests = const [],
  });

  final List<PullRequest> pullRequests;

  factory SessionResources.fromJson(Map<String, dynamic> json) {
    final prs = (json['pullRequests'] as List? ?? [])
        .map((e) => PullRequest.fromJson(e as Map<String, dynamic>))
        .toList();
    return SessionResources(pullRequests: prs);
  }
}

/// A pull request resource.
class PullRequest {
  PullRequest({
    this.owner,
    this.prId,
    this.repo,
    this.state,
  });

  final String? owner;
  final String? prId;
  final String? repo;
  final String? state;

  factory PullRequest.fromJson(Map<String, dynamic> json) => PullRequest(
        owner: json['owner'] as String?,
        prId: json['prId'] as String?,
        repo: json['repo'] as String?,
        state: json['state'] as String?,
      );
}

/// A provider resource (GitHub repo).
class ProviderResource {
  ProviderResource({
    required this.name,
    this.providerType,
    this.url,
    this.visibility,
  });

  final String name;
  final String? providerType;
  final String? url;
  final String? visibility;

  /// Display name (e.g. "owner/repo").
  String get displayName => name;

  factory ProviderResource.fromJson(Map<String, dynamic> json) =>
      ProviderResource(
        name: json['name'] as String? ?? '',
        providerType: json['providerType'] as String?,
        url: json['url'] as String?,
        visibility: json['visibility'] as String?,
      );
}

class AuthExpiredException implements Exception {}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

DateTime? _tryParseTimestamp(dynamic value) {
  if (value == null) return null;
  // Can be ISO string or epoch seconds.
  if (value is String) return DateTime.tryParse(value);
  if (value is num) {
    final ms = (value.toDouble() * 1000).toInt();
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
  return null;
}
