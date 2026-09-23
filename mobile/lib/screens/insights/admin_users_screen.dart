import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final admin = context.read<AdminProvider>();
      if (admin.users.isEmpty) admin.refresh();
    });
  }

  Future<void> _toggleRole(User u) async {
    final admin = context.read<AdminProvider>();
    final promote = !u.isAdmin;
    final ok = await confirmDialog(
      context,
      title: promote ? 'Make ${u.name} an admin?' : 'Remove admin from ${u.name}?',
      message: promote
          ? 'They will see fleet statistics and manage every user.'
          : 'They will only see their own scans afterwards.',
      confirmLabel: promote ? 'Promote' : 'Demote',
      destructive: !promote,
    );
    if (!ok || !mounted) return;
    try {
      await admin.setRole(u, promote ? 'admin' : 'user');
      if (mounted) showSnack(context, '${u.name} is now ${promote ? 'an admin' : 'a user'}');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete(User u) async {
    final admin = context.read<AdminProvider>();
    final ok = await confirmDialog(
      context,
      title: 'Delete ${u.name}?',
      message: 'Their account and every scan they made will be permanently removed.',
    );
    if (!ok || !mounted) return;
    try {
      await admin.deleteUser(u);
      if (mounted) showSnack(context, '${u.email} deleted');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final me = context.watch<AuthProvider>().user;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final q = _query.trim().toLowerCase();
    final users = admin.users.where((u) => q.isEmpty || u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [IconButton(onPressed: admin.refresh, icon: const Icon(Icons.refresh_rounded))],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                suffixIcon: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => setState(() => _query = '')),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: admin.refresh,
        child: admin.loading && admin.users.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : users.isEmpty
                ? ListView(children: const [SizedBox(height: 80), EmptyState(icon: Icons.person_search_rounded, title: 'No users match')])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final u = users[i];
                      final isMe = u.id == me?.id;
                      return NcCard(
                        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: (u.isAdmin ? NcColors.amber : scheme.primary).withValues(alpha: 0.2),
                              child: Text(u.initials, style: TextStyle(color: u.isAdmin ? NcColors.amber : scheme.primary, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(child: Text(u.name, style: t.titleSmall, overflow: TextOverflow.ellipsis)),
                                      if (isMe) ...[
                                        const SizedBox(width: 6),
                                        Text('(you)', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                                      ],
                                    ],
                                  ),
                                  Text(u.email, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (u.isAdmin ? NcColors.amber : scheme.primary).withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(u.role.toUpperCase(), style: t.labelSmall?.copyWith(color: u.isAdmin ? NcColors.amber : scheme.primary, letterSpacing: 0.6)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('joined ${Fmt.relative(u.createdAt)}', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              enabled: !isMe,
                              onSelected: (v) => v == 'role' ? _toggleRole(u) : _delete(u),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'role',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(u.isAdmin ? Icons.remove_moderator_outlined : Icons.add_moderator_outlined),
                                    title: Text(u.isAdmin ? 'Remove admin' : 'Make admin'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
                                    title: Text('Delete user', style: TextStyle(color: scheme.error)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ).animate(delay: (25 * (i % 15)).ms).fadeIn(duration: 220.ms).slideX(begin: 0.04, end: 0);
                    },
                  ),
      ),
    );
  }
}
