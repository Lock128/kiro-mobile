import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_manager.dart';
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
  List<ProviderResource> _repos = [];
  final List<ProviderResource> _selectedRepos = [];
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
      final repos = await widget.api.listProviderResources();
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

  void _removeRepo(ProviderResource repo) {
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
      // 1. Create the space with selected repos.
      final spaceId = await widget.api.createSpace(
        repos: _selectedRepos,
      );

      // 2. Get the main chat session for the space.
      final mainChat = await widget.api.getMainChatSession(spaceId: spaceId);
      final sessionId = mainChat.sessionId.isNotEmpty
          ? mainChat.sessionId
          : spaceId; // fallback: use spaceId as sessionId

      // 3. Send the user message.
      await widget.api.streamSendMessage(
        spaceId: spaceId,
        sessionId: sessionId,
        message: prompt,
      );

      if (!mounted) return;

      // 4. Navigate to the session detail view.
      _promptController.clear();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SessionDetailView(
            api: widget.api,
            spaceId: spaceId,
            sessionId: sessionId,
          ),
        ),
      );
    } on AuthExpiredException {
      if (mounted) context.read<AuthManager>().handleAuthError();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create space: $e')),
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
          Icon(Icons.smart_toy_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'What can I do for you today?',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
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
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                Icons.arrow_upward,
                                color: theme.colorScheme.primary,
                              ),
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary.withAlpha(30),
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

  final List<ProviderResource> repos;
  final List<ProviderResource> selectedRepos;
  final ValueChanged<ProviderResource> onSelected;

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

    return PopupMenuButton<ProviderResource>(
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


// ─── Chats Tab (now Spaces) ──────────────────────────────────────────────────

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key, required this.api});
  final KiroApi api;

  @override
  State<ChatsTab> createState() => ChatsTabState();
}

class ChatsTabState extends State<ChatsTab> {
  late Future<List<Space>> _future;
  String _sortColumn = 'updated';
  bool _sortAscending = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = widget.api.listSpaces();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void reload() {
    final f = widget.api.listSpaces();
    setState(() {
      _future = f;
    });
  }

  String _repoLabel(Space s) {
    if (s.githubRepo != null) {
      final fullName = s.githubRepo!['fullName'] as String?;
      if (fullName != null && fullName.isNotEmpty) return fullName;
    }
    final res = s.providerResources;
    if (res == null || res.isEmpty) return '';
    if (res.length > 1) return '${res.length} repos';
    final first = res.first;
    final name = first['name'] as String? ?? '';
    return name;
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

  List<Space> _sortAndFilter(List<Space> spaces) {
    var result = spaces.toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((s) {
        final name = s.name.toLowerCase();
        final repo = _repoLabel(s).toLowerCase();
        return name.contains(q) || repo.contains(q);
      }).toList();
    }

    result.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'name':
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'repository':
          cmp = _repoLabel(a).toLowerCase().compareTo(_repoLabel(b).toLowerCase());
        case 'type':
          cmp = (a.spaceType ?? '').compareTo(b.spaceType ?? '');
        case 'created':
          cmp = (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
        case 'updated':
        default:
          cmp = (a.updatedAt ?? DateTime(0)).compareTo(b.updatedAt ?? DateTime(0));
      }
      return _sortAscending ? cmp : -cmp;
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<Space>>(
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
            message: 'Failed to load spaces.',
            onRetry: () {
              final f = widget.api.listSpaces();
              setState(() => _future = f);
            },
          );
        }

        final allSpaces = snapshot.data ?? [];
        if (allSpaces.isEmpty) {
          return const Center(child: Text('No spaces yet.'));
        }

        final spaces = _sortAndFilter(allSpaces);

        return RefreshIndicator(
          onRefresh: () async {
            final f = widget.api.listSpaces();
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
                      1: FixedColumnWidth(80),
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
                          _SortableHeader(
                            label: 'Type',
                            column: 'type',
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
                      for (final s in spaces)
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
                                  final sessionId = s.sessionIds.isNotEmpty
                                      ? s.sessionIds.first
                                      : s.spaceId;
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => SessionDetailView(
                                        api: widget.api,
                                        spaceId: s.spaceId,
                                        sessionId: sessionId,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                  s.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            _TableCell(
                              child: Text(
                                s.spaceType ?? '',
                                style: theme.textTheme.bodySmall,
                              ),
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
                                s.updatedAt != null ? _formatDate(s.updatedAt!) : '',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (spaces.isEmpty && _searchQuery.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No spaces match your search.'),
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


// ─── Tasks Tab (now shows AUTONOMOUS spaces) ─────────────────────────────────

class TasksTab extends StatefulWidget {
  const TasksTab({super.key, required this.api});
  final KiroApi api;

  @override
  State<TasksTab> createState() => TasksTabState();
}

class TasksTabState extends State<TasksTab> {
  late Future<List<Space>> _future;
  String _sortColumn = 'updated';
  bool _sortAscending = false;
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

  Future<List<Space>> _loadTasks() async {
    final spaces = await widget.api.listSpaces();
    // Filter to only AUTONOMOUS spaces (tasks).
    return spaces.where((s) => s.isAutonomous).toList();
  }

  Future<void> _openTask(Space space) async {
    final sessionId = space.sessionIds.isNotEmpty
        ? space.sessionIds.first
        : space.spaceId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskDetailView(
          api: widget.api,
          space: space,
          sessionId: sessionId,
        ),
      ),
    );
  }

  String _repoLabel(Space s) {
    if (s.githubRepo != null) {
      final fullName = s.githubRepo!['fullName'] as String?;
      if (fullName != null && fullName.isNotEmpty) return fullName;
    }
    final res = s.providerResources;
    if (res == null || res.isEmpty) return '';
    if (res.length > 1) return '${res.length} repos';
    final first = res.first;
    return first['name'] as String? ?? '';
  }

  Widget _statusChip(String? status, ThemeData theme) {
    final label = status ?? 'unknown';
    final isActive = label.toUpperCase() == 'ACTIVE';
    final Color color;
    final IconData icon;
    if (isActive) {
      color = Colors.green;
      icon = Icons.check_circle_outline;
    } else {
      color = theme.colorScheme.onSurfaceVariant;
      icon = Icons.circle_outlined;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
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

  List<Space> _sortAndFilter(List<Space> spaces) {
    var result = spaces.toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((s) {
        final name = s.name.toLowerCase();
        final repo = _repoLabel(s).toLowerCase();
        return name.contains(q) || repo.contains(q);
      }).toList();
    }

    result.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'name':
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'status':
          cmp = (a.status ?? '').compareTo(b.status ?? '');
        case 'repository':
          cmp = _repoLabel(a).toLowerCase().compareTo(_repoLabel(b).toLowerCase());
        case 'created':
          cmp = (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
        case 'updated':
        default:
          cmp = (a.updatedAt ?? DateTime(0)).compareTo(b.updatedAt ?? DateTime(0));
      }
      return _sortAscending ? cmp : -cmp;
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<Space>>(
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

        final allTasks = snapshot.data ?? [];
        if (allTasks.isEmpty) {
          return const Center(child: Text('No tasks yet.'));
        }

        final tasks = _sortAndFilter(allTasks);

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
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(1.2),
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
                          _SortableHeader(label: 'Name', column: 'name', currentColumn: _sortColumn, ascending: _sortAscending, onTap: _onSort),
                          _SortableHeader(label: 'Status', column: 'status', currentColumn: _sortColumn, ascending: _sortAscending, onTap: _onSort),
                          _SortableHeader(label: 'Repository', column: 'repository', currentColumn: _sortColumn, ascending: _sortAscending, onTap: _onSort),
                          _SortableHeader(label: 'Created', column: 'created', currentColumn: _sortColumn, ascending: _sortAscending, onTap: _onSort),
                          _SortableHeader(label: 'Updated', column: 'updated', currentColumn: _sortColumn, ascending: _sortAscending, onTap: _onSort),
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
                                onTap: () => _openTask(t),
                                child: Text(
                                  t.name,
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
                                _repoLabel(t),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            _TableCell(
                              child: Text(
                                t.createdAt != null ? _formatDate(t.createdAt!) : '',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            _TableCell(
                              child: Text(
                                t.updatedAt != null ? _formatDate(t.updatedAt!) : '',
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
