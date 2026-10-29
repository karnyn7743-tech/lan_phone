import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/discovery/device_discovery.dart';
import '../../core/discovery/discovered_device.dart';
import '../../data/database/database_helper.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

/// ============================================================
/// شاشة المحادثات المؤرشفة
/// ============================================================
class ArchivedConversationsScreen extends StatefulWidget {
  const ArchivedConversationsScreen({super.key});

  @override
  State<ArchivedConversationsScreen> createState() =>
      _ArchivedConversationsScreenState();
}

class _ArchivedConversationsScreenState
    extends State<ArchivedConversationsScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows =
          await DatabaseHelper.instance.getArchivedConversations();
      if (!mounted) return;
      setState(() {
        _conversations = rows;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[Archived] load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unarchive(Map<String, dynamic> conv) async {
    final id = conv['conversation_id'] as String;
    await DatabaseHelper.instance.toggleArchive(id, false);
    HapticFeedback.lightImpact();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إلغاء الأرشفة'),
        duration: Duration(seconds: 2),
      ),
    );

    await _load();
  }

  Future<void> _delete(Map<String, dynamic> conv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever,
          color: AppTheme.errorColor,
          size: 40,
        ),
        title: const Text('حذف المحادثة'),
        content: const Text('سيتم حذف كل الرسائل نهائيًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final id = conv['conversation_id'] as String;
    final db = DatabaseHelper.instance;
    await db.deleteConversationMessages(id);
    await db.deleteConversation(id);

    await _load();
  }

  Future<void> _openChat(Map<String, dynamic> conv) async {
    final peerId = conv['peer_device_id'] as String;
    final discovery = context.read<DeviceDiscovery>();
    final peer = discovery.getDevice(peerId);

    if (peer == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الجهاز غير متوفر')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(peer: peer),
      ),
    );

    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المحادثات المؤرشفة'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          : _conversations.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _conversations.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 80),
                    itemBuilder: (context, index) {
                      final conv = _conversations[index];
                      return _ArchivedTile(
                        conversation: conv,
                        onTap: () => _openChat(conv),
                        onUnarchive: () => _unarchive(conv),
                        onDelete: () => _delete(conv),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.archive_outlined,
                size: 52,
                color: AppTheme.primaryColor.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'لا توجد محادثات مؤرشفة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'عند أرشفة أي محادثة، ستظهر هنا',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// === صف محادثة مؤرشفة ===
// ============================================================
class _ArchivedTile extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onTap;
  final VoidCallback onUnarchive;
  final VoidCallback onDelete;

  const _ArchivedTile({
    required this.conversation,
    required this.onTap,
    required this.onUnarchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final peerId = conversation['peer_device_id'] as String;
    final lastTime = conversation['last_message_time'] as int?;
    final unread = conversation['unread_count'] as int? ?? 0;

    final peer = context.select<DeviceDiscovery, DiscoveredDevice?>(
      (d) => d.getDevice(peerId),
    );

    final displayName = peer?.name ?? 'جهاز محذوف';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showOptions(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: isDark ? AppTheme.darkSurface : Colors.white,
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  displayName.isNotEmpty
                      ? displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.archive_outlined,
                          size: 13,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'مؤرشفة',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                        if (lastTime != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: TextStyle(
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(lastTime),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (unread > 0)
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 22,
                    minHeight: 22,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 99 ? '99+' : unread.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.unarchive,
                  color: AppTheme.primaryColor,
                ),
                title: const Text('إلغاء الأرشفة'),
                onTap: () {
                  Navigator.pop(ctx);
                  onUnarchive();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppTheme.errorColor,
                ),
                title: const Text(
                  'حذف المحادثة',
                  style: TextStyle(color: AppTheme.errorColor),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return DateFormat('h:mm a', 'ar').format(d);
    if (diff == 1) return 'أمس';
    if (diff < 7) return DateFormat('EEEE', 'ar').format(d);
    return DateFormat('d/M/yyyy', 'ar').format(d);
  }
}
