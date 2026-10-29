import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/discovery/device_discovery.dart';
import '../../../core/discovery/discovered_device.dart';
import '../../../core/messaging/message_service.dart';
import '../../../data/database/database_helper.dart';
import '../../theme/app_theme.dart';
import '../archived_conversations_screen.dart';
import '../chat_screen.dart';

/// ============================================================
/// تبويب المحادثات
/// ============================================================
class ConversationsTab extends StatefulWidget {
  const ConversationsTab({super.key});

  @override
  State<ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends State<ConversationsTab> {
  // ============================================
  // === الحالة ===
  // ============================================
  List<Map<String, dynamic>> _conversations = [];
  int _archivedCount = 0;
  bool _isLoading = true;

  MessageService? _messageService;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messageService = context.read<MessageService>();
      _messageService!.addListener(_onMessagesChanged);
      _loadConversations();
    });
  }

  @override
  void dispose() {
    _messageService?.removeListener(_onMessagesChanged);
    super.dispose();
  }

  // ============================================
  // === الاستماع والتحديث ===
  // ============================================

  void _onMessagesChanged() {
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      final db = DatabaseHelper.instance;
      final rows = await db.getVisibleConversations();
      final count = await db.getArchivedCount();

      if (!mounted) return;
      setState(() {
        _conversations = rows;
        _archivedCount = count;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[Conversations] load error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ============================================
  // === العمليات ===
  // ============================================

  Future<void> _deleteConversation(String conversationId) async {
    final db = DatabaseHelper.instance;
    await db.deleteConversationMessages(conversationId);
    await db.deleteConversation(conversationId);
    await _loadConversations();
  }

  Future<void> _togglePin(Map<String, dynamic> conv) async {
    final id = conv['conversation_id'] as String;
    final current = (conv['is_pinned'] as int?) == 1;

    await DatabaseHelper.instance.togglePin(id, !current);
    HapticFeedback.lightImpact();
    await _loadConversations();

    if (!mounted) return;
    _showSnack(current ? 'تم إلغاء التثبيت' : 'تم التثبيت');
  }

  Future<void> _toggleArchive(Map<String, dynamic> conv) async {
    final id = conv['conversation_id'] as String;
    final current = (conv['is_archived'] as int?) == 1;

    await DatabaseHelper.instance.toggleArchive(id, !current);
    HapticFeedback.mediumImpact();
    await _loadConversations();

    if (!mounted) return;
    _showSnack(current ? 'تم إلغاء الأرشفة' : 'تمت الأرشفة');
  }

  Future<void> _markAsRead(Map<String, dynamic> conv) async {
    final id = conv['conversation_id'] as String;
    await DatabaseHelper.instance.resetUnread(id);
    await _loadConversations();

    if (!mounted) return;
    _showSnack('تم تحديدها كمقروءة');
  }

  Future<void> _openConversation(Map<String, dynamic> conv) async {
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

    _loadConversations();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // === قائمة الخيارات ===
  // ============================================

  void _showOptions(Map<String, dynamic> conv) {
    final isPinned = (conv['is_pinned'] as int?) == 1;
    final isArchived = (conv['is_archived'] as int?) == 1;
    final unread = (conv['unread_count'] as int?) ?? 0;
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
              // مؤشر صغير
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // العنوان
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 20,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getPeerName(ctx, conv),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // الخيارات
              _OptionTile(
                icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: isPinned ? AppTheme.primaryColor : null,
                label: isPinned ? 'إلغاء التثبيت' : 'تثبيت في الأعلى',
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePin(conv);
                },
              ),

              _OptionTile(
                icon: isArchived ? Icons.unarchive : Icons.archive_outlined,
                color: isArchived ? AppTheme.primaryColor : null,
                label: isArchived ? 'إلغاء الأرشفة' : 'أرشفة',
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleArchive(conv);
                },
              ),

              if (unread > 0)
                _OptionTile(
                  icon: Icons.done_all,
                  label: 'تحديد كمقروءة',
                  onTap: () {
                    Navigator.pop(ctx);
                    _markAsRead(conv);
                  },
                ),

              Divider(
                height: 8,
                color: isDark
                    ? AppTheme.darkDivider
                    : AppTheme.lightDivider,
              ),

              _OptionTile(
                icon: Icons.delete_outline,
                color: AppTheme.errorColor,
                label: 'حذف المحادثة',
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(conv);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getPeerName(BuildContext context, Map<String, dynamic> conv) {
    final peerId = conv['peer_device_id'] as String;
    final discovery = context.read<DeviceDiscovery>();
    final peer = discovery.getDevice(peerId);
    return peer?.name ?? 'جهاز محذوف';
  }

  Future<void> _confirmDelete(Map<String, dynamic> conv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever,
          color: AppTheme.errorColor,
          size: 40,
        ),
        title: const Text('حذف المحادثة'),
        content: const Text(
          'سيتم حذف كل الرسائل في هذه المحادثة نهائيًا.\n'
          'لا يمكن التراجع عن هذه العملية.',
        ),
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

    if (ok == true) {
      await _deleteConversation(conv['conversation_id'] as String);
    }
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    if (_conversations.isEmpty && _archivedCount == 0) {
      return const _EmptyConversationsState();
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      child: Column(
        children: [
          // شريط المؤرشفة
          if (_archivedCount > 0) _buildArchivedBar(),

          // قائمة المحادثات
          Expanded(
            child: _conversations.isEmpty
                ? const _EmptyVisibleState()
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _conversations.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 80),
                    itemBuilder: (context, index) {
                      final conv = _conversations[index];
                      return _ConversationTile(
                        conversation: conv,
                        onTap: () => _openConversation(conv),
                        onLongPress: () => _showOptions(conv),
                        onSwipeArchive: () => _toggleArchive(conv),
                        onSwipeDelete: () => _confirmDelete(conv),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // === شريط المؤرشفة ===
  // ============================================

  Widget _buildArchivedBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ArchivedConversationsScreen(),
            ),
          );
          _loadConversations();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? AppTheme.darkDivider
                    : AppTheme.lightDivider,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.archive_outlined,
                  color: AppTheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'المحادثات المؤرشفة',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'محادثات مخفية عن القائمة الرئيسية',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_archivedCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_left,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// === صف محادثة ===
// ============================================================
class _ConversationTile extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSwipeArchive;
  final VoidCallback onSwipeDelete;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
    required this.onSwipeArchive,
    required this.onSwipeDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final peerId = conversation['peer_device_id'] as String;
    final lastMessage = conversation['last_message'] as String? ?? '';
    final lastType = conversation['last_message_type'] as String? ?? 'text';
    final lastTime = conversation['last_message_time'] as int?;
    final unread = conversation['unread_count'] as int? ?? 0;
    final isPinned = (conversation['is_pinned'] as int?) == 1;
    final isArchived = (conversation['is_archived'] as int?) == 1;

    final isOnline = context.select<DeviceDiscovery, bool>(
      (d) => d.isDeviceOnline(peerId),
    );

    final peer = context.select<DeviceDiscovery, DiscoveredDevice?>(
      (d) => d.getDevice(peerId),
    );

    final displayName = peer?.name ?? 'جهاز محذوف';
    final peerNumber = peer?.number ?? '';

    return Dismissible(
      key: ValueKey(conversation['conversation_id']),
      // ✅ سحب يمين = أرشفة
      // ✅ سحب يسار = حذف
      background: _swipeBackground(
        alignment: AlignmentDirectional.centerStart,
        color: AppTheme.warningColor,
        icon: isArchived ? Icons.unarchive : Icons.archive,
        label: isArchived ? 'إلغاء الأرشفة' : 'أرشفة',
      ),
      secondaryBackground: _swipeBackground(
        alignment: AlignmentDirectional.centerEnd,
        color: AppTheme.errorColor,
        icon: Icons.delete_outline,
        label: 'حذف',
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onSwipeArchive();
          return false; // لا تحذف الصف
        }
        if (direction == DismissDirection.endToStart) {
          onSwipeDelete();
          return false; // لا تحذف الصف (الحذف يتم عبر Dialog)
        }
        return false;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            color: isDark ? AppTheme.darkSurface : Colors.white,
            child: Row(
              children: [
                // الأفاتار
                _ConversationAvatar(
                  name: displayName,
                  isOnline: isOnline,
                  isPinned: isPinned,
                ),

                const SizedBox(width: 14),

                // المحتوى
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // الاسم + الوقت
                      Row(
                        children: [
                          if (isPinned) ...[
                            const Icon(
                              Icons.push_pin,
                              size: 14,
                              color: AppTheme.primaryColor,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: unread > 0
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: isDark
                                          ? AppTheme.darkTextPrimary
                                          : AppTheme.lightTextPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (peerNumber.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor
                                          .withOpacity(0.12),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '#$peerNumber',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryColor,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (lastTime != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              _formatTime(lastTime),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: unread > 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: unread > 0
                                    ? AppTheme.primaryColor
                                    : (isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary),
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 5),

                      // آخر رسالة + شارة
                      Row(
                        children: [
                          if (lastType != AppConstants.mediaText) ...[
                            Icon(
                              _iconForType(lastType),
                              size: 15,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              _previewText(lastMessage, lastType),
                              style: TextStyle(
                                fontSize: 14,
                                color: unread > 0
                                    ? (isDark
                                        ? AppTheme.darkTextPrimary
                                        : AppTheme.lightTextPrimary)
                                    : (isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary),
                                fontWeight: unread > 0
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unread > 0) ...[
                            const SizedBox(width: 8),
                            _UnreadBadge(count: unread),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _swipeBackground({
    required AlignmentDirectional alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case AppConstants.mediaImage:
        return Icons.image_outlined;
      case AppConstants.mediaVideo:
        return Icons.videocam_outlined;
      case AppConstants.mediaAudio:
        return Icons.mic_none;
      case AppConstants.mediaFile:
        return Icons.insert_drive_file_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  String _previewText(String text, String type) {
    switch (type) {
      case AppConstants.mediaImage:
        return 'صورة';
      case AppConstants.mediaVideo:
        return 'فيديو';
      case AppConstants.mediaAudio:
        return 'مقطع صوتي';
      case AppConstants.mediaFile:
        return text.isEmpty ? 'ملف' : text;
      default:
        return text.isEmpty ? 'لا توجد رسائل' : text;
    }
  }

  String _formatTime(int timestamp) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) {
      return DateFormat('h:mm a', 'ar').format(d);
    }
    if (diff == 1) return 'أمس';
    if (diff < 7) return DateFormat('EEEE', 'ar').format(d);
    return DateFormat('d/M/yyyy', 'ar').format(d);
  }
}

// ============================================================
// === الأفاتار ===
// ============================================================
class _ConversationAvatar extends StatelessWidget {
  final String name;
  final bool isOnline;
  final bool isPinned;

  const _ConversationAvatar({
    required this.name,
    required this.isOnline,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isOnline
                  ? [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0.75),
                    ]
                  : [
                      Colors.grey.shade400,
                      Colors.grey.shade600,
                    ],
            ),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // نقطة الاتصال
        Positioned(
          bottom: 1,
          right: 1,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: isOnline ? AppTheme.successColor : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 2.5,
              ),
            ),
          ),
        ),
        // شارة التثبيت
        if (isPinned)
          Positioned(
            top: -2,
            left: -2,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.push_pin,
                size: 11,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================
// === شارة غير المقروء ===
// ============================================================
class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
    );
  }
}

// ============================================================
// === خيار في القائمة السفلية ===
// ============================================================
class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkTextPrimary
            : AppTheme.lightTextPrimary);

    return ListTile(
      leading: Icon(icon, color: effectiveColor),
      title: Text(
        label,
        style: TextStyle(
          color: effectiveColor,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}

// ============================================================
// === حالات فارغة ===
// ============================================================
class _EmptyConversationsState extends StatelessWidget {
  const _EmptyConversationsState();

  @override
  Widget build(BuildContext context) {
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
              child: const Icon(
                Icons.chat_bubble_outline,
                size: 52,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'لا توجد محادثات',
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
              'اذهب إلى تبويب "الأجهزة" وابدأ محادثة\n'
              'مع جهاز على نفس شبكة الواي فاي',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyVisibleState extends StatelessWidget {
  const _EmptyVisibleState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.archive_outlined,
                  size: 64,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'لا توجد محادثات نشطة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'كل محادثاتك مؤرشفة',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
