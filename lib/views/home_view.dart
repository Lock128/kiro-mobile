import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_manager.dart';
import '../services/debug_log.dart';
import '../services/kiro_api.dart';
import 'session_detail_view.dart';
import 'task_detail_view.dart';

// ─── Create Tab ──────────────────────────────────────────────────────────────

class CreateTab extends StatefulWidget {
  const CreateTab({super.key, required this.api});
  final KiroApi api;

  @override
  State<CreateTab> createState() => _CreateTabState();
}

class _CreateTabState extends State<CreateTab> {
  final _promptController = TextEditingController();
  List<ConnectionResource> _repos = [];
  final List<ConnectionResource> _selectedRepos = [];
  bool _loadingRepos = true;
  String? _repoError;

  @override
  void initState() {
    super.initState();
    _loadRepos();
  }

  Future<void> _loadRepos() async {
    setState(() {
      _loadingRepos = true;
      _repoError = null;
    });
    try {
      final repos = await widget.api.listConnectionResources();
      repos.sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      if (mounted) {
        setState(() {
          _repos = repos;
          _loadingRepos = false;
        });
      }
    } on AuthExpiredException {
      if (mounted) {
        context.read<AuthManager>().handleAuthError();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _repoError = 'Failed to load repositories.';
          _loadingRepos = false;
        });
      }
    }
  }

  bool _submitting = false;

  void _removeRepo(ConnectionResource repo) {
    setState(() => _selectedRepos.remove(repo));
  }

  Future<void> _submit() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _selectedRepos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a prompt and select at least one repo.'),
        ),
      );
      return;
    }
    if (_submitting) return;

    setState(() => _submitting = true);

    try {
      // 1. Create the session with selected repos.
      final sessionId = await widget.api.createSession(
        repos: _selectedRepos,
      );

      // 2. Ensure the session is ready on the backend.
      await widget.api.getSession(sessionId: sessionId);

      // 3. Send the user message.
      await widget.api.generateAgentSessionResponse(
        sessionId: sessionId,
        message: prompt,
      );

      if (!mounted) return;

      // 3. Navigate to the session detail view.
      _promptController.clear();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SessionDetailView(
            api: widget.api,
            sessionId: sessionId,
          ),
        ),
      );
    } on AuthExpiredException {
      if (mounted) context.read<AuthManager>().handleAuthError();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create session: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          // Ghost icon
          Icon(Icons.smart_toy_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'What can I do for you today?',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          // Prompt text field
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _promptController,
                  maxLines: 4,
                  minLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Ask a question or describe a task…',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8, right: 8),
                  child: Row(
                    children: [
                      Text(
                        'New line  shift+enter',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                Icons.arrow_upward,
                                color: theme.colorScheme.primary,
                              ),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              theme.colorScheme.primary.withAlpha(30),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Repo selector
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _loadingRepos
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _repoError != null
                    ? Row(
                        children: [
                          Text(_repoError!,
                              style: TextStyle(color: theme.colorScheme.error)),
                          const Spacer(),
                          TextButton(
                              onPressed: _loadRepos, child: const Text('Retry')),
                        ],
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ..._selectedRepos.map(
                            (repo) => Chip(
                              label: Text(repo.displayName),
                              onDeleted: () => _removeRepo(repo),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          _RepoDropdown(
                            repos: _repos,
                            selectedRepos: _selectedRepos,
                            onSelected: (repo) {
                              setState(() => _selectedRepos.add(repo));
                            },
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

/// Inline dropdown for selecting repos, filtering out already-selected ones.
class _RepoDropdown extends StatelessWidget {
  const _RepoDropdown({
    required this.repos,
    required this.selectedRepos,
    required this.onSelected,
  });

  final List<ConnectionResource> repos;
  final List<ConnectionResource> selectedRepos;
  final ValueChanged<ConnectionResource> onSelected;

  @override
  Widget build(BuildContext context) {
    final available = repos
        .where((r) => !selectedRepos.any((s) => s.name == r.name))
        .toList();

    if (available.isEmpty) {
      return Text(
        'No more repos',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }

    return PopupMenuButton<ConnectionResource>(
      onSelected: onSelected,
      itemBuilder: (_) => available
          .map((r) => PopupMenuItem(value: r, child: Text(r.displayName)))
          .toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Select repo(s)',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.unfold_more,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}


// ─── Chats Tab ───────────────────────────────────────────────────────────────

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key, required this.api});
  final KiroApi api;

  @override
  State<ChatsTab> createState() => ChatsTabState();
}

class ChatsTabState extends State<ChatsTab> {
  late Future<List<ChatSession>> _future;
  String _sortColumn = 'updated';
  bool _sortAscending = false; // descending by default
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = widget.api.listSessions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void reload() {
    final f = widget.api.listSessions();
    setState(() {
      _future = f;
    });
  }

  String _repoLabel(ChatSession s) {
    final res = s.providerResources;
    if (res == null || res.isEmpty) return '';
    if (res.length > 1) return '${res.length} repos';
    final gh = res.first['github'] as Map<String, dynamic>?;
    if (gh == null) return '';
    final owner = gh['owner'] as String? ?? '';
    final name = gh['name'] as String? ?? '';
    if (owner.isNotEmpty && name.isNotEmpty) return '$owner/$name';
    return name;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = column == 'name'; // default asc for name, desc for dates
      }
    });
  }

  List<ChatSession> _sortAndFilter(List<ChatSession> sessions) {
    var result = sessions.toList();

    // Filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((s) {
        final name = s.displayName.toLowerCase();
        final repo = _repoLabel(s).toLowerCase();
        return name.contains(q) || repo.contains(q);
      }).toList();
    }

    // Sort
    result.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'name':
          cmp = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        case 'repository':
          cmp = _repoLabel(a).toLowerCase().compareTo(_repoLabel(b).toLowerCase());
        case 'created':
          cmp = (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
        case 'updated':
        default:
          cmp = (a.lastUpdatedAt ?? DateTime(0)).compareTo(b.lastUpdatedAt ?? DateTime(0));
      }
      return _sortAscending ? cmp : -cmp;
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<ChatSession>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (snapshot.error is AuthExpiredException) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.read<AuthManager>().handleAuthError();
            });
            return const Center(child: Text('Session expired. Signing out…'));
          }
          return _ErrorRetry(
            message: 'Failed to load chats.',
            onRetry: () {
              final f = widget.api.listSessions();
              setState(() => _future = f);
            },
          );
        }

        final allSessions = snapshot.data ?? [];
        if (allSessions.isEmpty) {
          return const Center(child: Text('No chats yet.'));
        }

        final sessions = _sortAndFilter(allSessions);

        return RefreshIndicator(
          onRefresh: () async {
            final f = widget.api.listSessions();
            setState(() => _future = f);
            await f;
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  _SearchBar(
                    controller: _searchController,
                    hintText: 'Search by name or repository…',
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                  const SizedBox(height: 8),
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FixedColumnWidth(48),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(1.2),
                      4: FlexColumnWidth(1.2),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        children: [
                          _SortableHeader(
                            label: 'Name',
                            column: 'name',
                            currentColumn: _sortColumn,
                            ascending: _sortAscending,
                            onTap: _onSort,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Tooltip(
                              message: 'Has task',
                              child: Icon(Icons.task_alt,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          _SortableHeader(
                            label: 'Repository',
                            column: 'repository',
                            currentColumn: _sortColumn,
                            ascending: _sortAscending,
                            onTap: _onSort,
                          ),
                          _SortableHeader(
                            label: 'Created',
                            column: 'created',
                            currentColumn: _sortColumn,
                            ascending: _sortAscending,
                            onTap: _onSort,
                          ),
                          _SortableHeader(
                            label: 'Updated',
                            column: 'updated',
                            currentColumn: _sortColumn,
                            ascending: _sortAscending,
                            onTap: _onSort,
                          ),
                        ],
                      ),
                      for (final s in sessions)
                        TableRow(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: theme.colorScheme.outlineVariant.withAlpha(80),
                              ),
                            ),
                          ),
                          children: [
                            _TableCell(
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => SessionDetailView(
                                        api: widget.api,
                                        sessionId: s.sessionId,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                  s.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            _TableCell(
                              child: s.isTask
                                  ? Icon(Icons.check,
                                      size: 18,
                                      color: theme.colorScheme.onSurfaceVariant)
                                  : const SizedBox.shrink(),
                            ),
                            _TableCell(
                              child: Text(
                                _repoLabel(s),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            _TableCell(
                              child: Text(
                                s.createdAt != null ? _formatDate(s.createdAt!) : '',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            _TableCell(
                              child: Text(
                                s.lastUpdatedAt != null ? _formatDate(s.lastUpdatedAt!) : '',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (sessions.isEmpty && _searchQuery.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No chats match your search.'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: child,
    );
  }
}

// ─── Tasks Tab ───────────────────────────────────────────────────────────────

class TasksTab extends StatefulWidget {
  const TasksTab({super.key, required this.api});
  final KiroApi api;

  @override
  State<TasksTab> createState() => TasksTabState();
}

class TasksTabState extends State<TasksTab> {
  late Future<_TasksData> _future;
  String _sortColumn = 'updated';
  bool _sortAscending = false; // descending by default
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _loadTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void reload() {
    final f = _loadTasks();
    setState(() {
      _future = f;
    });
  }

  Future<_TasksData> _loadTasks() async {
    final results = await Future.wait([
      widget.api.listAgentTasks(),
      widget.api.listSessions(),
    ]);
    final tasks = results[0] as List<AgentTask>;
    final sessions = results[1] as List<ChatSession>;
    final sessionByTaskId = <String, ChatSession>{};
    for (final s in sessions) {
      if (s.taskId != null && s.taskId!.isNotEmpty) {
        sessionByTaskId[s.taskId!] = s;
      }
    }
    DebugLog.log('_loadTasks: ${tasks.length} tasks, ${sessions.length} sessions, ${sessionByTaskId.length} mapped');
    for (final t in tasks.take(3)) {
      final matched = sessionByTaskId.containsKey(t.taskId);
      DebugLog.log('  task "${t.taskId}" matched=$matched');
    }
    return _TasksData(tasks: tasks, sessionByTaskId: sessionByTaskId);
  }

  Future<void> _openTask(AgentTask task, Map<String, ChatSession> sessionByTaskId) async {
    final session = sessionByTaskId[task.taskId];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskDetailView(
          api: widget.api,
          task: task,
          session: session,
        ),
      ),
    );
  }

  String _repoLabel(AgentTask task, Map<String, ChatSession> sessionByTaskId) {
    // Prefer providerResources directly on the task if available.
    var res = task.providerResources;
    // Fall back to the session lookup.
    if (res == null || res.isEmpty) {
      final session = sessionByTaskId[task.taskId];
      if (session == null) return '';
      res = session.providerResources;
    }
    if (res == null || res.isEmpty) return '';
    if (res.length > 1) return '${res.length} repos';
    final gh = res.first['github'] as Map<String, dynamic>?;
    if (gh == null) return '';
    final owner = gh['owner'] as String? ?? '';
    final name = gh['name'] as String? ?? '';
    if (owner.isNotEmpty && name.isNotEmpty) return '$owner/$name';
    return name;
  }

  String _sourceLabel(AgentTask task) {
    final src = task.sourceProvider;
    if (src == null || src.isEmpty) return '';
    if (src.contains('BIGWEAVER')) return 'Kiro';
    return src;
  }

  Widget _statusChip(String? status, ThemeData theme) {
    final label = status ?? 'unknown';
    final isCompleted = label.toUpperCase() == 'COMPLETED';
    final isInProgress =
        label.toUpperCase() == 'IN_PROGRESS' || label.toUpperCase() == 'RUNNING';
    final Color color;
    final IconData icon;
    if (isCompleted) {
      color = Colors.green;
      icon = Icons.check_circle_outline;
    } else if (isInProgress) {
      color = Colors.orange;
      icon = Icons.autorenew;
    } else {
      color = theme.colorScheme.onSurfaceVariant;
      icon = Icons.circle_outlined;
    }
    final display = label
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(display, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = column == 'name';
      }
    });
  }

  List<AgentTask> _sortAndFilter(List<AgentTask> tasks, Map<String, ChatSession> sessionMap) {
    var result = tasks.toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((t) {
        final name = (t.name ?? '').toLowerCase();
        final repo = _repoLabel(t, sessionMap).toLowerCase();
        return name.contains(q) || repo.contains(q);
      }).toList();
    }

    result.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'name':
          cmp = (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
        case 'status':
          cmp = (a.status ?? '').compareTo(b.status ?? '');
        case 'repository':
          cmp = _repoLabel(a, sessionMap).toLowerCase().compareTo(
              _repoLabel(b, sessionMap).toLowerCase());
        case 'created':
          cmp = (a.createdTime ?? DateTime(0)).compareTo(b.createdTime ?? DateTime(0));
        case 'updated':
        default:
          cmp = (a.lastUpdatedTime ?? DateTime(0)).compareTo(b.lastUpdatedTime ?? DateTime(0));
      }
      return _sortAscending ? cmp : -cmp;
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<_TasksData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (snapshot.error is AuthExpiredException) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.read<AuthManager>().handleAuthError();
            });
            return const Center(child: Text('Session expired. Signing out…'));
          }
          return _ErrorRetry(
            message: 'Failed to load tasks.',
            onRetry: () {
              final f = _loadTasks();
              setState(() => _future = f);
            },
          );
        }

        final data = snapshot.data!;
        final allTasks = data.tasks;
        final sessionMap = data.sessionByTaskId;

        if (allTasks.isEmpty) {
          return const Center(child: Text('No tasks yet.'));
        }

        final tasks = _sortAndFilter(allTasks, sessionMap);

        return RefreshIndicator(
          onRefresh: () async {
            final f = _loadTasks();
            setState(() => _future = f);
            await f;
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  _SearchBar(
                    controller: _searchController,
                    hintText: 'Search by name or repository…',
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                  const SizedBox(height: 8),
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2.5),
                      1: FlexColumnWidth(1.5),
                      2: FlexColumnWidth(2),
                      3: FixedColumnWidth(48),
                      4: FlexColumnWidth(1.2),
                      5: FlexColumnWidth(1.2),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        children: [
                          _SortableHeader(
                            label: 'Name',
                            column: 'name',
                            currentColumn: _sortColumn,
                            ascending: _sortAscending,
                            onTap: _onSort,
                          ),
                          _SortableHeader(
                            label: 'Task status',
                            column: 'status',
                            currentColumn: _sortColumn,
                            ascending: _sortAscending,
                            onTap: _onSort,
                          ),
                          _SortableHeader(
                            label: 'Repository',
                            column: 'repository',
                            currentColumn: _sortColumn,
                            ascending: _sortAscending,
                            onTap: _onSort,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text('Source',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                )),
                          ),
                          _SortableHeader(
                            label: 'Created',
                            column: 'created',
                            currentColumn: _sortColumn,
                            ascending: _sortAscending,
                            onTap: _onSort,
                          ),
                          _SortableHeader(
                            label: 'Updated',
                            column: 'updated',
                            currentColumn: _sortColumn,
                            ascending: _sortAscending,
                            onTap: _onSort,
                          ),
                        ],
                      ),
                      for (final t in tasks)
                        TableRow(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: theme.colorScheme.outlineVariant.withAlpha(80),
                              ),
                            ),
                          ),
                          children: [
                            _TableCell(
                              child: InkWell(
                                onTap: () => _openTask(t, sessionMap),
                                child: Text(
                                  t.name ?? 'Untitled task',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            _TableCell(child: _statusChip(t.status, theme)),
                            _TableCell(
                              child: Text(
                                _repoLabel(t, sessionMap),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            _TableCell(
                              child: Text(
                                _sourceLabel(t),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            _TableCell(
                              child: Text(
                                t.createdTime != null
                                    ? _formatDate(t.createdTime!)
                                    : '',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            _TableCell(
                              child: Text(
                                t.lastUpdatedTime != null
                                    ? _formatDate(t.lastUpdatedTime!)
                                    : '',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (tasks.isEmpty && _searchQuery.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No tasks match your search.'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TasksData {
  _TasksData({required this.tasks, required this.sessionByTaskId});
  final List<AgentTask> tasks;
  final Map<String, ChatSession> sessionByTaskId;
}

// ─── Shared ──────────────────────────────────────────────────────────────────

class _SortableHeader extends StatelessWidget {
  const _SortableHeader({
    required this.label,
    required this.column,
    required this.currentColumn,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final String column;
  final String currentColumn;
  final bool ascending;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = currentColumn == column;

    return InkWell(
      onTap: () => onTap(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 2),
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.month}/${dt.day}/${dt.year}';
}
