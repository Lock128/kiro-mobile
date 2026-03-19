import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/auth_credentials.dart';

/// Client for the Kiro / CodeWhisperer API.
class KiroApi {
  KiroApi({required AuthCredentials credentials, http.Client? httpClient})
      : _credentials = credentials,
        _client = httpClient ?? http.Client();

  final AuthCredentials _credentials;
  final http.Client _client;

  static const _baseUrl = 'https://codewhisperer.us-east-1.amazonaws.com';
  static const _profileArn =
      'arn:aws:codewhisperer:us-east-1:638616132270:profile/AAAACCCCXXXX';

  // Cached after first fetch.
  String? _instanceId;
  String? _connectionId;

  static const _uuid = Uuid();

  static String get _osLabel {
    if (kIsWeb) return 'web';
    // defaultTargetPlatform is safe on non-web.
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
        'accept': '*/*',
        'content-type': 'application/json',
        if (_credentials.bearerToken != null)
          'authorization': 'Bearer ${_credentials.bearerToken}',
        if (_credentials.csrfToken != null)
          'x-csrf-token': _credentials.csrfToken!,
        'x-amz-user-agent':
            'aws-sdk-js/1.0.0 ua/2.1 os/$_osLabel lang/js api/bigweaver#1.0.0',
        'amz-sdk-invocation-id': _uuid.v4(),
        'amz-sdk-request': 'attempt=1; max=1',
      };

  /// Resolves the instanceId by calling ListInstances (cached after first call).
  Future<String> _getInstanceId() async {
    if (_instanceId != null) return _instanceId!;

    final response = await _client.post(
      Uri.parse('$_baseUrl/ListInstances'),
      headers: _headers,
      body: jsonEncode({'profileArn': _profileArn}),
    );
    _checkResponse(response, 'ListInstances');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final instances = data['instances'] as List? ?? [];
    if (instances.isEmpty) throw ApiException('No instances found');

    _instanceId =
        (instances.first as Map<String, dynamic>)['instanceId'] as String;
    return _instanceId!;
  }

  /// Resolves the connectionId by calling ListConnections (cached after first call).
  Future<String> _getConnectionId() async {
    if (_connectionId != null) return _connectionId!;

    final instanceId = await _getInstanceId();
    final response = await _client.post(
      Uri.parse('$_baseUrl/ListConnections'),
      headers: _headers,
      body: jsonEncode({
        'instanceId': instanceId,
        'connectionTypes': ['github', 'githubUser'],
        'profileArn': _profileArn,
      }),
    );
    _checkResponse(response, 'ListConnections');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final ids = (data['connectionIds'] as List? ?? []).cast<String>();
    if (ids.isEmpty) throw ApiException('No connections found');

    _connectionId = ids.first;
    return _connectionId!;
  }

  /// Fetches all chat sessions (handles pagination).
  /// Caps at [maxPages] pages to prevent runaway loops.
  Future<List<ChatSession>> listSessions({
    int maxResults = 50,
    int maxPages = 20,
  }) async {
    final instanceId = await _getInstanceId();
    final allSessions = <ChatSession>[];
    String? nextToken;
    var page = 0;

    do {
      final body = <String, dynamic>{
        'instanceId': instanceId,
        'maxResults': maxResults,
        'profileArn': _profileArn,
      };
      if (nextToken != null) body['nextToken'] = nextToken;

      final response = await _client.post(
        Uri.parse('$_baseUrl/listSessions'),
        headers: _headers,
        body: jsonEncode(body),
      );
      _checkResponse(response, 'listSessions');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final prevToken = nextToken;
      nextToken = data['nextToken'] as String?;
      // Guard against the API returning the same token repeatedly.
      if (nextToken == prevToken) break;

      final sessions = data['sessions'] as List? ?? [];
      for (final e in sessions) {
        allSessions.add(ChatSession.fromJson(e as Map<String, dynamic>));
      }
      page++;
    } while (nextToken != null && page < maxPages);

    return allSessions;
  }

  /// Fetches all agent tasks (handles pagination).
  /// Caps at [maxPages] pages to prevent runaway loops.
  Future<List<AgentTask>> listAgentTasks({
    int maxResults = 50,
    int maxPages = 20,
  }) async {
    final instanceId = await _getInstanceId();
    final allTasks = <AgentTask>[];
    String? nextToken;
    var page = 0;

    do {
      final body = <String, dynamic>{
        'instanceId': instanceId,
        'maxResults': maxResults,
        'profileArn': _profileArn,
      };
      if (nextToken != null) body['nextToken'] = nextToken;

      final response = await _client.post(
        Uri.parse('$_baseUrl/listAgentTasks'),
        headers: _headers,
        body: jsonEncode(body),
      );
      _checkResponse(response, 'listAgentTasks');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final prevToken = nextToken;
      nextToken = data['nextToken'] as String?;
      if (nextToken == prevToken) break;

      final items = data['items'] as List? ?? [];
      for (final e in items) {
        allTasks.add(AgentTask.fromJson(e as Map<String, dynamic>));
      }
      page++;
    } while (nextToken != null && page < maxPages);

    return allTasks;
  }

  /// Fetches all repositories the user has access to (handles pagination).
  Future<List<ConnectionResource>> listConnectionResources() async {
    final instanceId = await _getInstanceId();
    final connectionId = await _getConnectionId();

    final allResources = <ConnectionResource>[];
    String? nextToken;

    do {
      final body = <String, dynamic>{
        'connectionId': connectionId,
        'instanceId': instanceId,
        'maxResults': 50,
        'profileArn': _profileArn,
      };
      if (nextToken != null) body['nextToken'] = nextToken;

      final response = await _client.post(
        Uri.parse('$_baseUrl/ListConnectionResources'),
        headers: _headers,
        body: jsonEncode(body),
      );
      _checkResponse(response, 'ListConnectionResources');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      nextToken = data['nextToken'] as String?;

      final resources = data['resources'] as List? ?? [];
      for (final r in resources) {
        final map = r as Map<String, dynamic>;
        // Response shape: {"githubUser": {"owner": "...", "repo": "...", "visibility": "..."}}
        final gh = map['githubUser'] as Map<String, dynamic>?;
        if (gh != null) {
          allResources.add(ConnectionResource(
            name: gh['repo'] as String? ?? '',
            owner: gh['owner'] as String?,
            visibility: gh['visibility'] as String?,
          ));
        }
      }
    } while (nextToken != null);

    return allResources;
  }

  void _checkResponse(http.Response response, String operation) {
    if (response.statusCode == 401) throw AuthExpiredException();
    if (response.statusCode == 403) throw AuthExpiredException();
    if (response.statusCode != 200) {
      throw ApiException('$operation failed: ${response.statusCode}');
    }
  }

  /// Creates a new session with the given repos. Returns the sessionId.
  Future<String> createSession({
    required List<ConnectionResource> repos,
  }) async {
    final instanceId = await _getInstanceId();
    final connectionId = await _getConnectionId();

    final providerResources = repos
        .map((r) => {
              'github': {
                'providerId': connectionId,
                'name': r.name,
                'owner': r.owner ?? '',
              }
            })
        .toList();

    final response = await _client.post(
      Uri.parse('$_baseUrl/createSession'),
      headers: _headers,
      body: jsonEncode({
        'instanceId': instanceId,
        'profileArn': _profileArn,
        'providerResources': providerResources,
      }),
    );
    _checkResponse(response, 'createSession');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['sessionId'] as String;
  }

  /// Fetches session details. Also used to ensure the session is ready
  /// on the backend before sending a message.
  Future<Map<String, dynamic>> getSession({
    required String sessionId,
  }) async {
    final instanceId = await _getInstanceId();
    final response = await _client.post(
      Uri.parse('$_baseUrl/getSession'),
      headers: _headers,
      body: jsonEncode({
        'instanceId': instanceId,
        'sessionId': sessionId,
        'profileArn': _profileArn,
      }),
    );
    _checkResponse(response, 'getSession');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Sends a user message to an existing session (fire-and-forget streaming call).
  /// Returns immediately — poll [listSessionHistory] for updates.
  Future<void> generateAgentSessionResponse({
    required String sessionId,
    required String message,
  }) async {
    final instanceId = await _getInstanceId();

    // This is a streaming endpoint. We send the request and don't wait
    // for the full streamed response — the caller should poll
    // listSessionHistory for updates.
    final request = http.Request(
      'POST',
      Uri.parse('$_baseUrl/generateAgentSessionResponse'),
    );
    request.headers.addAll(_headers);
    request.body = jsonEncode({
      'instanceId': instanceId,
      'sessionId': sessionId,
      'prompt': message,
      'profileArn': _profileArn,
    });

    final streamed = await _client.send(request);
    if (streamed.statusCode == 401 || streamed.statusCode == 403) {
      throw AuthExpiredException();
    }
    if (streamed.statusCode != 200) {
      throw ApiException(
          'generateAgentSessionResponse failed: ${streamed.statusCode}');
    }
    // Drain the stream so the connection is released.
    await streamed.stream.drain<void>();
  }

  /// Fetches the session history (messages and activities).
  Future<SessionHistory> listSessionHistory({
    required String sessionId,
  }) async {
    final instanceId = await _getInstanceId();
    final response = await _client.post(
      Uri.parse('$_baseUrl/listSessionHistory'),
      headers: _headers,
      body: jsonEncode({
        'instanceId': instanceId,
        'sessionId': sessionId,
        'profileArn': _profileArn,
        'sortOrder': 'descending',
      }),
    );
    _checkResponse(response, 'listSessionHistory');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return SessionHistory.fromJson(data);
  }

  void dispose() => _client.close();
}

// ─── Models ──────────────────────────────────────────────────────────────────

class ChatSession {
  ChatSession({
    required this.sessionId,
    this.name,
    this.createdAt,
    this.lastUpdatedAt,
    this.taskId,
    this.providerResources,
  });

  final String sessionId;
  final String? name;
  final DateTime? createdAt;
  final DateTime? lastUpdatedAt;
  final String? taskId;
  final List<Map<String, dynamic>>? providerResources;

  /// Whether this session is associated with a task.
  bool get isTask => taskId != null && taskId!.isNotEmpty;

  /// Human-readable display name: session name, repo info, or session ID prefix.
  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    // Fallback: show the first repo name from providerResources.
    if (providerResources != null && providerResources!.isNotEmpty) {
      final first = providerResources!.first;
      final gh = first['github'] as Map<String, dynamic>?;
      if (gh != null) {
        final owner = gh['owner'] as String? ?? '';
        final repoName = gh['name'] as String? ?? '';
        if (owner.isNotEmpty && repoName.isNotEmpty) return '$owner/$repoName';
        if (repoName.isNotEmpty) return repoName;
      }
    }
    // Last resort: truncated session ID.
    return 'Session ${sessionId.substring(0, 8)}…';
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        sessionId: json['sessionId'] as String? ?? '',
        name: json['name'] as String?,
        createdAt: _tryParseDate(json['createdAt']),
        lastUpdatedAt: _tryParseDate(json['lastUpdatedAt']),
        taskId: json['taskId'] as String?,
        providerResources: (json['providerResources'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}

class AgentTask {
  AgentTask({
    required this.taskId,
    this.name,
    this.title,
    this.status,
    this.sourceProvider,
    this.createdTime,
    this.lastUpdatedTime,
    this.providerResources,
  });

  final String taskId;
  final String? name;
  final String? title;
  final String? status;
  final String? sourceProvider;
  final DateTime? createdTime;
  final DateTime? lastUpdatedTime;
  final List<Map<String, dynamic>>? providerResources;

  factory AgentTask.fromJson(Map<String, dynamic> json) => AgentTask(
        taskId: json['taskId'] as String? ?? '',
        name: json['name'] as String?,
        title: json['title'] as String?,
        status: json['status'] as String?,
        sourceProvider: json['sourceProvider'] as String?,
        createdTime: _tryParseEpoch(json['createdTime']),
        lastUpdatedTime: _tryParseEpoch(json['lastUpdatedTime']),
        providerResources: (json['providerResources'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}

class ConnectionResource {
  ConnectionResource({required this.name, this.owner, this.visibility});

  final String name;
  final String? owner;
  final String? visibility;

  String get displayName =>
      owner != null && owner!.isNotEmpty ? '$owner/$name' : name;
}

class AuthExpiredException implements Exception {}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// History of a session including messages and activities.
class SessionHistory {
  SessionHistory({
    required this.sessionId,
    this.messages = const [],
    this.activities = const [],
  });

  final String sessionId;
  final List<SessionMessage> messages;
  final List<SessionMessage> activities;

  factory SessionHistory.fromJson(Map<String, dynamic> json) {
    final activities = (json['activities'] as List? ?? [])
        .map((e) => SessionMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    final messages = (json['messages'] as List? ?? [])
        .map((e) => SessionMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    return SessionHistory(
      sessionId: json['sessionId'] as String? ?? '',
      messages: messages,
      activities: activities,
    );
  }
}

/// A single message or activity in a session.
class SessionMessage {
  SessionMessage({required this.role, this.content, this.timestamp, this.agentName});

  final String role;
  final String? content;
  final DateTime? timestamp;
  final String? agentName;

  factory SessionMessage.fromJson(Map<String, dynamic> json) {
    // Content can be nested: {text: {content: "..."}} or {toolResult: {...}}
    String? content;
    final rawContent = json['content'];
    if (rawContent is Map<String, dynamic>) {
      final text = rawContent['text'];
      if (text is Map<String, dynamic>) {
        content = text['content'] as String?;
      } else if (text is String) {
        content = text;
      }
      // For tool results, extract a summary.
      final toolResult = rawContent['toolResult'];
      if (toolResult != null && content == null) {
        final items = (toolResult as Map<String, dynamic>)['content'] as List?;
        if (items != null && items.isNotEmpty) {
          final first = items.first as Map<String, dynamic>;
          content = first['text'] as String?;
        }
      }
    }

    return SessionMessage(
      role: json['role'] as String? ?? 'unknown',
      content: content,
      timestamp: _tryParseDate(json['timestamp']),
      agentName: json['agentName'] as String?,
    );
  }
}

DateTime? _tryParseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

/// Parses epoch seconds (e.g. 1766481772.966) to DateTime.
DateTime? _tryParseEpoch(dynamic value) {
  if (value == null) return null;
  try {
    final seconds = (value as num).toDouble();
    return DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).toInt(),
      isUtc: true,
    );
  } catch (_) {
    return null;
  }
}
