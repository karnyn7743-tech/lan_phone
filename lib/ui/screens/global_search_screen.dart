import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/discovery/discovered_device.dart';
import '../../data/database/database_helper.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

/// ============================================================
/// البحث العالمي في كل المحادثات
/// ============================================================
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  // ============================================
  // === المراجع ===
  // ============================================
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // ============================================
  // === الحالة ===
  // ============================================
  Timer? _debounce;
  String _query = '';
  bool _isSearching = false;
  List<Map<String, dynamic>> _results = [];
  Map<String, int> _stats = {'total': 0, 'conversations': 0};

  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);

    // تركيز تلقائي على الحقل
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _focus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================
  // === البحث ===
  // ============================================

  void _onQueryChanged() {
    final text = _controller.text.trim();

    _debounce?.cancel();

    // إذا مسح المستخدم → أفرغ النتائج فورًا
    if (text.isEmpty) {
      setState(() {
        _query = '';
        _results = [];
        _stats = {'total': 0, 'conversations': 0};
        _isSearching = false;
      });
      return;
    }

    // إذا كان البحث جديدًا → فعّل حالة البحث
    setState(() {
      _query = text;
      _isSearching = true;
    });

    // debounce 300ms
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(text);
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final results =
          await DatabaseHelper.instance.searchMessages(query: query);
      final stats = await DatabaseHelper.instance.getSearchStats(query);

      if (!mounted) return;
      // تأكد أن الاستعلام لم يتغيّر
      if (_controller.text.trim() != query) return;

      setState(() {
        _results = results;
        _stats = stats;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('[GlobalSearch] error: $e');
      if (!mounted) return;
      setState(() {
        _results = [];
        _isSearching = false;
      });
    }
  }

  void _clear() {
    _controller.clear();
    _focus.requestFocus();
  }

  // ============================================
  // === فتح المحادثة ===
  // ============================================

  Future<void> _openResult(Map<String, dynamic> result) async {
    // معرّف الجهاز المرسل
    final peerDeviceId = (result['conversation_peer_id'] ??
            result['peer_id'] ??
            '') as String;

    if (peerDeviceId.isEmpty) {
      _showError('تعذّر تحديد الجهاز');
      return;
    }

    final discovery = context.read<DeviceDiscovery>();
    DiscoveredDevice? peer = discovery.getDevice(peerDeviceId);

    // إذا لم نجده في الاكتشاف → جرّب من قاعدة البيانات
    if (peer == null) {
      try {
        final row =
            await DatabaseHelper.instance.getDevice(peerDeviceId);
        if (row != null) {
          peer = DiscoveredDevice(
            deviceId: row['device_id'] as String,
            number: (row['number'] as String?) ?? '',
            name: row['name'] as String,
            ip: row['ip_address'] as String,
            port: row['port'] as int,
            capabilities: const [],
            lastSeen: DateTime.fromMillisecondsSinceEpoch(
              row['last_seen'] as int,
            ),
            isOnline: false,
          );
        }
      } catch (e) {
        debugPrint('[GlobalSearch] fetch device error: $e');
      }
    }

    if (peer == null) {
      _showError('الجهاز غير متوفر');
      return;
    }

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          peer: peer!,
          highlightMessageId: result['message_id'] as String?,
        ),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.errorColor,
      ),
    );
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: _buildAppBar(isDark),
      body: _buildBody(isDark),
    );
  }

  // ============================================
  // === AppBar بالبحث ===
  // ============================================

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      titleSpacing: 0,
      title: TextField(
        controller: _controller,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          hintText: 'ابحث في كل الرسائل...',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
      actions: [
        // حالة البحث
        if (_query.isNotEmpty && !_isSearching && _stats['total']! > 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${_stats['total']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        // زر مسح
        if (_query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'مسح',
            onPressed: _clear,
          ),
      ],
    );
  }

  // ============================================
  // === الجسم ===
  // ============================================

  Widget _buildBody(bool isDark) {
    // حالة فارغة - لم يُكتب شيء
    if (_query.isEmpty) {
      return _buildEmptyState(isDark);
    }

    // جارٍ البحث
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    // لا نتائج
    if (_results.isEmpty) {
      return _buildNoResultsState(isDark);
    }

    // نتائج
    return _buildResults(isDark);
  }

  // ============================================
  // === حالة فارغة (لا يوجد استعلام) ===
  // ============================================

  Widget _buildEmptyState(bool isDark) {
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
                Icons.search,
                size: 52,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'ابحث في كل المحادثات',
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
              'اكتب كلمة أو جملة للبحث في محتوى الرسائل\n'
              'وأسماء الملفات',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // === حالة "لا نتائج" ===
  // ============================================

  Widget _buildNoResultsState(bool isDark) {
    final textColor =
        isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 72, color: textColor),
            const SizedBox(height: 16),
            Text(
              'لا توجد نتائج',
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
              'لم يتم العثور على رسائل تحتوي على\n"$_query"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // === قائمة النتائج ===
  // ============================================

  Widget _buildResults(bool isDark) {
    // جمّع النتائج حسب المحادثة
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final result in _results) {
      final key = result['conversation_id'] as String? ?? 'unknown';
      grouped.putIfAbsent(key, () => []).add(result);
    }

    // حوّل إلى قائمة
    final sections = grouped.entries.toList();

    // ابنِ عناصر القائمة المسطّحة
    final items = <Widget>[];
    for (final section in sections) {
      final messages = section.value;

      if (messages.isEmpty) continue;

      // اسم الجهاز والرقم
      final first = messages.first;
      final peerName =
          (first['peer_name'] as String?) ?? 'جهاز محذوف';
      final peerNumber = (first['peer_number'] as String?) ?? '';

      // رأس القسم
      items.add(_buildSectionHeader(
        peerName: peerName,
        peerNumber: peerNumber,
        count: messages.length,
        isDark: isDark,
      ));

      // الرسائل
      for (final msg in messages) {
        items.add(_buildResultTile(
          message: msg,
          peerName: peerName,
          isDark: isDark,
        ));
      }

      // مسافة بين الأقسام
      items.add(const SizedBox(height: 8));
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // شريط ملخّص
        _buildStatsBar(isDark),
        ...items,
        const SizedBox(height: 40),
      ],
    );
  }

  // ============================================
  // === شريط الإحصائيات ===
  // ============================================

  Widget _buildStatsBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search,
            size: 18,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_stats['total']} نتيجة في ${_stats['conversations']} محادثة',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // === رأس قسم المحادثة ===
  // ============================================

  Widget _buildSectionHeader({
    required String peerName,
    required String peerNumber,
    required int count,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              peerName,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
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
                horizontal: 6,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '#$peerNumber',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.darkDivider
                  : AppTheme.lightDivider,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // === صف نتيجة ===
  // ============================================

  Widget _buildResultTile({
    required Map<String, dynamic> message,
    required String peerName,
    required bool isDark,
  }) {
    final type = message['type'] as String?;
    final body = message['body'] as String? ?? '';
    final fileName = message['file_name'] as String?;
    final createdAt = message['created_at'] as int;
    final isOutgoing = (message['is_outgoing'] as int?) == 1;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openResult(message),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // السطر الأول: نوع + وقت
              Row(
                children: [
                  Icon(
                    _iconForType(type),
                    size: 14,
                    color: AppTheme.primaryColor.withOpacity(0.7),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isOutgoing ? 'صادر' : 'وارد',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // محتوى الرسالة مع إبراز
              if (type == AppConstants.mediaText)
                _buildHighlightedText(
                  body,
                  highlight: _query,
                  isDark: isDark,
                  maxLines: 3,
                )
              else
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        fileName ?? _mediaLabel(type),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.lightTextPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String? type) {
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

  String _mediaLabel(String? type) {
    switch (type) {
      case AppConstants.mediaImage:
        return 'صورة';
      case AppConstants.mediaVideo:
        return 'فيديو';
      case AppConstants.mediaAudio:
        return 'مقطع صوتي';
      case AppConstants.mediaFile:
        return 'ملف';
      default:
        return 'مرفق';
    }
  }

  // ============================================
  // === نص مع إبراز ===
  // ============================================

  Widget _buildHighlightedText(
    String text, {
    required String highlight,
    required bool isDark,
    int maxLines = 3,
  }) {
    final baseStyle = TextStyle(
      fontSize: 14,
      height: 1.4,
      color:
          isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
    );

    if (highlight.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = highlight.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + highlight.length),
        style: TextStyle(
          backgroundColor: Colors.yellow.withOpacity(0.5),
          color: isDark ? Colors.black : Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = index + highlight.length;
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ============================================
  // === تنسيق الوقت ===
  // ============================================

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
    if (diff < 7) {
      return DateFormat('EEEE', 'ar').format(d);
    }
    return DateFormat('d/M/yyyy', 'ar').format(d);
  }
}
