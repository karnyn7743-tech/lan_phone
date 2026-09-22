import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/discovery/device_discovery.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/messaging/message_service.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/services/app_lifecycle_service.dart';
import '../../core/services/audio_recorder_service.dart';
import '../../data/database/database_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/permission_dialog.dart';
import '../widgets/voice_message_bubble.dart';
import 'audio_call_screen.dart';
import 'forward_message_screen.dart';
import 'video_call_screen.dart';
import 'video_player_screen.dart';

/// ============================================================
/// شاشة المحادثة
/// ============================================================
class ChatScreen extends StatefulWidget {
  final DiscoveredDevice peer;
  final String? highlightMessageId;

  const ChatScreen({
    super.key,
    required this.peer,
    this.highlightMessageId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // ============================================
  // === المراجع ===
  // ============================================
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  MessageService? _messageService;
  AppLifecycleService? _lifecycleService;
  StreamSubscription<MessageEvent>? _eventSub;

  // ✅ استماع لأحداث WebRTC (لفتح شاشة المكالمة الواردة)
  StreamSubscription<RtcEvent>? _rtcEventSub;

  // ============================================
  // === الحالة ===
  // ============================================
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _filteredMessages = [];
  bool _isLoading = true;
  String? _replyToId;
  Map<String, dynamic>? _replyToMessage;
  bool _canSend = false;
  bool _isSendingMedia = false;
  String? _multiSendProgress;

  bool _isSearching = false;
  String _searchQuery = '';

  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  final List<double> _waveform = [];

  String? _highlightedMessageId;

  List<Map<String, dynamic>> _pinnedMessages = [];
  int _currentPinnedIndex = 0;

  late String _conversationId;

  // ============================================
  // === دورة الحياة ===
  // ============================================

  @override
  void initState() {
    super.initState();

    _highlightedMessageId = widget.highlightMessageId;

    _inputController.addListener(() {
      final can = _inputController.text.trim().isNotEmpty;
      if (can != _canSend) {
        setState(() => _canSend = can);
      }
    });

    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _searchQuery) {
        setState(() {
          _searchQuery = q;
          _applyFilter();
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _messageService = context.read<MessageService>();
      _lifecycleService = context.read<AppLifecycleService>();
      final discovery = context.read<DeviceDiscovery>();
      _conversationId = _buildConversationId(
        discovery.deviceId,
        widget.peer.deviceId,
      );

      _eventSub = _messageService!.events.listen(_onMessageEvent);

      // ✅ استمع لأحداث WebRTC لفتح شاشة المكالمة عند ورودها
      _rtcEventSub = context.read<RtcService>().events.listen(_onRtcEvent);

      _lifecycleService!.setOpenChat(widget.peer.deviceId);

      await _loadMessages();
      await _loadPinnedMessages();
      await _messageService!.markConversationAsRead(widget.peer.deviceId);

      if (_highlightedMessageId != null) {
        _scrollToMessage(_highlightedMessageId!);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _highlightedMessageId = null);
        });
      }
    });
  }

  @override
  void dispose() {
    _lifecycleService?.clearOpenChat();
    _eventSub?.cancel();
    _rtcEventSub?.cancel();
    _recordingTimer?.cancel();
    AudioRecorderService.instance.cancel();
    _inputController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ============================================
  // === ✅ معالجة أحداث WebRTC ===
  // ============================================

  void _onRtcEvent(RtcEvent event) {
    if (!mounted) return;
    if (event.type != RtcEventType.incomingCall) return;
    if (event.peerDeviceId != widget.peer.deviceId) return;

    // افتح الشاشة المناسبة كـ "مستقبِل"
    if (event.callType == AppConstants.callTypeVideo) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            peer: widget.peer,
            isCaller: false,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AudioCallScreen(
            peer: widget.peer,
            isCaller: false,
          ),
        ),
      );
    }
  }

  // ============================================
  // === أدوات ===
  // ============================================

  String _buildConversationId(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}__${sorted[1]}';
  }

  Future<void> _loadMessages() async {
    try {
      final rows = await DatabaseHelper.instance.getMessages(
        conversationId: _conversationId,
      );
      if (!mounted) return;
      setState(() {
        _messages = rows;
        _isLoading = false;
        _applyFilter();
      });
      _scrollToBottom(animated: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPinnedMessages() async {
    try {
      final rows = await DatabaseHelper.instance.getPinnedMessages(
        _conversationId,
      );
      if (!mounted) return;
      setState(() {
        _pinnedMessages = rows;
        if (_pinnedMessages.isEmpty) {
          _currentPinnedIndex = 0;
        } else if (_currentPinnedIndex >= _pinnedMessages.length) {
          _currentPinnedIndex = 0;
        }
      });
    } catch (e) {
      debugPrint('[Chat] loadPinned error: $e');
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredMessages = _messages;
      return;
    }
    final q = _searchQuery.toLowerCase();
    _filteredMessages = _messages.where((m) {
      final type = m['type'] as String?;
      if (type == AppConstants.mediaText) {
        final body = (m['body'] as String?)?.toLowerCase() ?? '';
        return body.contains(q);
      }
      if (type == AppConstants.mediaFile) {
        final fileName = (m['file_name'] as String?)?.toLowerCase() ?? '';
        return fileName.contains(q);
      }
      return false;
    }).toList();
  }

  void _onMessageEvent(MessageEvent event) {
    if (event.peerDeviceId != widget.peer.deviceId) return;
    switch (event.type) {
      case MessageEventType.received:
      case MessageEventType.sent:
      case MessageEventType.ack:
        _loadMessages();
        _loadPinnedMessages();
        if (event.type == MessageEventType.received) {
          _messageService?.markConversationAsRead(widget.peer.deviceId);
        }
        break;
      default:
        break;
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(max);
      }
    });
  }

  void _scrollToMessage(String messageId) {
    final items = _filteredMessages.reversed.toList();
    final index = items.indexWhere((m) => m['message_id'] == messageId);
    if (index == -1) return;

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!_scrollController.hasClients) return;
      final targetOffset = (index * 80.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });

    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  // ============================================
  // === التنقل بين المثبتات ===
  // ============================================

  void _nextPinnedMessage() {
    if (_pinnedMessages.isEmpty) return;

    setState(() {
      _currentPinnedIndex =
          (_currentPinnedIndex + 1) % _pinnedMessages.length;
    });

    final messageId = _pinnedMessages[_currentPinnedIndex]['message_id']
        as String;
    _scrollToMessage(messageId);
  }

  void _unpinCurrent() async {
    if (_pinnedMessages.isEmpty) return;

    final current = _pinnedMessages[_currentPinnedIndex];
    await _togglePin(current, unpinOnly: true);
  }

  void _showAllPinned() {
    if (_pinnedMessages.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PinnedMessagesSheet(
        pinnedMessages: _pinnedMessages,
        currentIndex: _currentPinnedIndex,
        onSelect: (index, messageId) {
          Navigator.pop(ctx);
          setState(() => _currentPinnedIndex = index);
          _scrollToMessage(messageId);
        },
        onUnpin: (message) {
          Navigator.pop(ctx);
          _togglePin(message, unpinOnly: true);
        },
      ),
    );
  }

  // ============================================
  // === تثبيت / إلغاء تثبيت ===
  // ============================================

  Future<void> _togglePin(
    Map<String, dynamic> message, {
    bool unpinOnly = false,
  }) async {
    try {
      final messageId = message['message_id'] as String;
      final isPinned = (message['is_pinned'] as int?) == 1;

      if (unpinOnly && !isPinned) return;

      final newValue = unpinOnly ? false : !isPinned;

      await DatabaseHelper.instance.toggleMessagePin(
        messageId,
        newValue,
      );

      HapticFeedback.mediumImpact();

      await _loadMessages();
      await _loadPinnedMessages();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? 'تم تثبيت الرسالة' : 'تم إلغاء التثبيت'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('[Chat] togglePin error: $e');
    }
  }

  // ============================================
  // === البحث ===
  // ============================================

  void _enterSearchMode() {
    setState(() {
      _isSearching = true;
      _searchQuery = '';
      _searchController.clear();
      _filteredMessages = _messages;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _searchFocus.requestFocus();
    });
  }

  void _exitSearchMode() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
      _filteredMessages = _messages;
    });
  }

  // ============================================
  // === قائمة خيارات الرسالة ===
  // ============================================

  void _showMessageOptions(Map<String, dynamic> message) {
    HapticFeedback.mediumImpact();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final type = message['type'] as String?;
    final isOutgoing = (message['is_outgoing'] as int?) == 1;
    final isText = type == AppConstants.mediaText;
    final body = message['body'] as String? ?? '';
    final hasText = body.isNotEmpty;
    final isPinned = (message['is_pinned'] as int?) == 1;

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

              _OptionItem(
                icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                label: isPinned ? 'إلغاء التثبيت' : 'تثبيت',
                color: isPinned ? AppTheme.primaryColor : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePin(message);
                },
              ),

              _OptionItem(
                icon: Icons.reply,
                label: 'رد',
                onTap: () {
                  Navigator.pop(ctx);
                  _startReply(message);
                },
              ),

              _OptionItem(
                icon: Icons.forward,
                label: 'توجيه',
                onTap: () {
                  Navigator.pop(ctx);
                  _forwardMessage(message);
                },
              ),

              if (isText && hasText)
                _OptionItem(
                  icon: Icons.copy_outlined,
                  label: 'نسخ النص',
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyMessage(body);
                  },
                ),

              Divider(
                height: 8,
                color: isDark
                    ? AppTheme.darkDivider
                    : AppTheme.lightDivider,
              ),

              if (isOutgoing)
                _OptionItem(
                  icon: Icons.delete_outline,
                  label: 'حذف',
                  color: AppTheme.errorColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteMessage(message);
                  },
                )
              else
                _OptionItem(
                  icon: Icons.info_outline,
                  label: 'معلومات الرسالة',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMessageInfo(message);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // === توجيه الرسالة ===
  // ============================================

  Future<void> _forwardMessage(Map<String, dynamic> message) async {
    final result = await Navigator.of(context).push<ForwardResult>(
      MaterialPageRoute(
        builder: (_) => ForwardMessageScreen(message: message),
      ),
    );

    if (!mounted || result == null) return;

    final String text;
    final Color color;

    if (result.allSucceeded) {
      text = 'تم التوجيه إلى ${result.successCount} جهاز';
      color = AppTheme.successColor;
    } else if (result.partial) {
      text = 'نجح ${result.successCount} وفشل ${result.failCount}';
      color = AppTheme.warningColor;
    } else {
      text = 'فشل التوجيه';
      color = AppTheme.errorColor;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // === نسخ الرسالة ===
  // ============================================

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ النص'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // === حذف الرسالة ===
  // ============================================

  Future<void> _confirmDeleteMessage(Map<String, dynamic> message) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever,
          size: 40,
          color: AppTheme.errorColor,
        ),
        title: const Text('حذف الرسالة'),
        content: const Text(
          'سيتم حذف هذه الرسالة نهائيًا من جهازك.\n'
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

    if (confirm != true) return;

    try {
      final messageId = message['message_id'] as String;
      await DatabaseHelper.instance.deleteMessage(messageId);
      HapticFeedback.mediumImpact();
      await _loadMessages();
      await _loadPinnedMessages();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الرسالة'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('[Chat] deleteMessage error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر حذف الرسالة'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  // ============================================
  // === معلومات الرسالة ===
  // ============================================

  void _showMessageInfo(Map<String, dynamic> message) {
    final sentAt = DateTime.fromMillisecondsSinceEpoch(
      message['created_at'] as int,
    );
    final deliveredAt = message['delivered_at'] as int?;
    final readAt = message['read_at'] as int?;
    final status = message['status'] as String? ?? 'unknown';

    String statusText;
    switch (status) {
      case 'pending':
        statusText = 'قيد الإرسال';
        break;
      case 'sent':
        statusText = 'تم الإرسال';
        break;
      case 'delivered':
        statusText = 'تم التسليم';
        break;
      case 'read':
        statusText = 'تم القراءة';
        break;
      case 'failed':
        statusText = 'فشل';
        break;
      default:
        statusText = status;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('معلومات الرسالة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('الحالة', statusText),
            const SizedBox(height: 8),
            _infoRow(
              'أُرسلت',
              DateFormat('d/M/y - h:mm a', 'ar').format(sentAt),
            ),
            if (deliveredAt != null) ...[
              const SizedBox(height: 8),
              _infoRow(
                'سُلّمت',
                DateFormat('d/M/y - h:mm a', 'ar').format(
                  DateTime.fromMillisecondsSinceEpoch(deliveredAt),
                ),
              ),
            ],
            if (readAt != null) ...[
              const SizedBox(height: 8),
              _infoRow(
                'قُرِئت',
                DateFormat('d/M/y - h:mm a', 'ar').format(
                  DateTime.fromMillisecondsSinceEpoch(readAt),
                ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // === الإرسال ===
  // ============================================

  Future<void> _sendText() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _messageService == null) return;

    _inputController.clear();

    final replyId = _replyToId;
    setState(() {
      _replyToId = null;
      _replyToMessage = null;
    });

    await _messageService!.sendText(
      peerDeviceId: widget.peer.deviceId,
      body: text,
      replyToId: replyId,
    );

    _scrollToBottom();
  }

  void _startReply(Map<String, dynamic> message) {
    HapticFeedback.lightImpact();
    setState(() {
      _replyToId = message['message_id'] as String;
      _replyToMessage = message;
    });
    _inputFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyToId = null;
      _replyToMessage = null;
    });
  }

  // ============================================
  // === تسجيل صوتي ===
  // ============================================

  Future<void> _startRecording() async {
    if (_isRecording) return;

    final recorder = AudioRecorderService.instance;

    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      final granted = await PermissionDialog.ensure(
        context,
        permissions: <ph.Permission>[ph.Permission.microphone],
        title: 'الميكروفون',
        message: 'نحتاج الميكروفون لتسجيل الرسائل الصوتية',
        icon: Icons.mic,
      );
      if (!granted) return;
    }

    final path = await recorder.start();
    if (path == null || !mounted) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
      _waveform.clear();
    });

    _recordingTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= 300) _stopAndSendRecording();
      },
    );

    recorder.getAmplitudeStream().listen((amp) {
      if (!mounted || !_isRecording) return;
      final normalized = ((amp.current + 60) / 60).clamp(0.05, 1.0);
      setState(() {
        _waveform.add(normalized);
        if (_waveform.length > 40) _waveform.removeAt(0);
      });
    });
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    final result = await AudioRecorderService.instance.stop();

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
      _waveform.clear();
    });

    if (result == null) {
      _showError('التسجيل قصير جدًا');
      return;
    }

    setState(() => _isSendingMedia = true);

    final replyId = _replyToId;
    setState(() {
      _replyToId = null;
      _replyToMessage = null;
    });

    try {
      final sendResult = await _messageService!.sendMedia(
        peerDeviceId: widget.peer.deviceId,
        filePath: result.path,
        mediaType: AppConstants.mediaAudio,
        replyToId: replyId,
      );

      if (!sendResult.ok && mounted) {
        _showError(sendResult.error ?? 'فشل إرسال المقطع');
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) _showError('فشل الإرسال: $e');
    } finally {
      if (mounted) setState(() => _isSendingMedia = false);
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await AudioRecorderService.instance.cancel();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
      _waveform.clear();
    });
  }

  // ============================================
  // === فتح الوسائط ===
  // ============================================

  void _openImage(String filePath) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _ImageViewerScreen(filePath: filePath),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _openVideo(String filePath, {String? title}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoPath: filePath,
          title: title,
        ),
      ),
    );
  }

  Future<void> _openFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (!mounted) return;
        _showError('الملف غير موجود');
        return;
      }
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done && mounted) {
        _showError('لا يوجد تطبيق لفتح هذا الملف');
      }
    } catch (e) {
      debugPrint('[Chat] openFile error: $e');
      if (mounted) _showError('تعذّر فتح الملف');
    }
  }

  // ============================================
  // === فحص إصدار Android ===
  // ============================================

  Future<int> _getAndroidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (e) {
      debugPrint('[Chat] _getAndroidSdkInt error: $e');
      return 0;
    }
  }

  // ============================================
  // === الأذونات حسب النوع والإصدار ===
  // ============================================

  Future<List<ph.Permission>> _getRequiredPermissions(
    String mediaType,
  ) async {
    if (mediaType == AppConstants.mediaFile) {
      return [];
    }

    final sdkInt = await _getAndroidSdkInt();

    if (!Platform.isAndroid) {
      return [ph.Permission.photos];
    }

    if (sdkInt >= 33) {
      if (mediaType == AppConstants.mediaImage) {
        return [ph.Permission.photos];
      } else if (mediaType == AppConstants.mediaVideo) {
        return [ph.Permission.videos];
      }
      return [];
    }

    return [ph.Permission.storage];
  }

  // ============================================
  // === اختيار وإرسال الوسائط ===
  // ============================================

  Future<void> _pickAndSendMedia(String mediaType) async {
    if (_isSendingMedia) return;

    final permissions = await _getRequiredPermissions(mediaType);

    if (permissions.isNotEmpty) {
      bool alreadyGranted = true;
      for (final p in permissions) {
        final status = await p.status;
        if (!status.isGranted && !status.isLimited) {
          alreadyGranted = false;
          break;
        }
      }

      if (!alreadyGranted) {
        if (!mounted) return;

        final granted = await PermissionDialog.ensure(
          context,
          permissions: permissions,
          title: mediaType == AppConstants.mediaImage
              ? 'الوصول للصور'
              : 'الوصول للفيديو',
          message: 'نحتاج الإذن لاختيار الوسائط',
          icon: Icons.photo_library_outlined,
        );

        if (!granted || !mounted) {
          _showError('لم يتم منح الإذن');
          return;
        }
      }
    }

    if (!mounted) return;

    if (mediaType == AppConstants.mediaImage) {
      await _pickAndSendMultipleImages();
      return;
    }

    String? pickedPath;

    try {
      if (mediaType == AppConstants.mediaVideo) {
        pickedPath = await _pickVideo();
      } else {
        pickedPath = await _pickFile();
      }
    } catch (e) {
      debugPrint('[Chat] pick error: $e');
      _showError('تعذّر اختيار الملف');
      return;
    }

    if (pickedPath == null || !mounted) return;

    setState(() => _isSendingMedia = true);

    final replyId = _replyToId;
    setState(() {
      _replyToId = null;
      _replyToMessage = null;
    });

    try {
      final result = await _messageService!.sendMedia(
        peerDeviceId: widget.peer.deviceId,
        filePath: pickedPath,
        mediaType: mediaType,
        replyToId: replyId,
      );

      if (!result.ok && mounted) {
        _showError(result.error ?? 'فشل الإرسال');
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) _showError('فشل الإرسال: $e');
    } finally {
      if (mounted) setState(() => _isSendingMedia = false);
    }
  }

  // ============================================
  // === إرسال متعدد للصور ===
  // ============================================

  Future<void> _pickAndSendMultipleImages() async {
    List<String> paths;

    try {
      final picker = ImagePicker();
      final List<XFile> files = await picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
      );

      if (files.isEmpty || !mounted) return;

      paths = files.map((f) => f.path).toList();
    } catch (e) {
      debugPrint('[Chat] pickMultiImage error: $e');
      _showError('تعذّر اختيار الصور');
      return;
    }

    if (paths.length == 1) {
      await _sendSingleImage(paths.first);
      return;
    }

    setState(() => _isSendingMedia = true);

    final replyId = _replyToId;
    setState(() {
      _replyToId = null;
      _replyToMessage = null;
    });

    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < paths.length; i++) {
      if (mounted) {
        setState(() {
          _multiSendProgress = 'إرسال ${i + 1}/${paths.length}';
        });
      }

      try {
        final result = await _messageService!.sendMedia(
          peerDeviceId: widget.peer.deviceId,
          filePath: paths[i],
          mediaType: AppConstants.mediaImage,
          replyToId: i == 0 ? replyId : null,
        );

        if (result.ok) {
          successCount++;
        } else {
          failCount++;
        }
      } catch (e) {
        debugPrint('[Chat] send image $i error: $e');
        failCount++;
      }
    }

    if (!mounted) return;

    setState(() {
      _isSendingMedia = false;
      _multiSendProgress = null;
    });

    _scrollToBottom();

    HapticFeedback.mediumImpact();

    final String message;
    final Color color;

    if (failCount == 0) {
      message = 'تم إرسال $successCount ${successCount == 1 ? "صورة" : "صور"} بنجاح';
      color = AppTheme.successColor;
    } else if (successCount == 0) {
      message = 'فشل إرسال $failCount من الصور';
      color = AppTheme.errorColor;
    } else {
      message = 'نجح $successCount وفشل $failCount';
      color = AppTheme.warningColor;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _sendSingleImage(String path) async {
    setState(() => _isSendingMedia = true);

    final replyId = _replyToId;
    setState(() {
      _replyToId = null;
      _replyToMessage = null;
    });

    try {
      final result = await _messageService!.sendMedia(
        peerDeviceId: widget.peer.deviceId,
        filePath: path,
        mediaType: AppConstants.mediaImage,
        replyToId: replyId,
      );

      if (!result.ok && mounted) {
        _showError(result.error ?? 'فشل الإرسال');
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) _showError('فشل الإرسال: $e');
    } finally {
      if (mounted) setState(() => _isSendingMedia = false);
    }
  }

  // ============================================
  // === منتقي الفيديو والملفات ===
  // ============================================

  Future<String?> _pickVideo() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    return file?.path;
  }

  Future<String?> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return null;
      return result.files.first.path;
    } catch (e) {
      debugPrint('[Chat] _pickFile error: $e');
      return null;
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.errorColor,
      ),
    );
  }

  // ============================================
  // === المكالمات ===
  // ============================================

  Future<void> _startAudioCall() async {
    final granted = await PermissionDialog.ensure(
      context,
      permissions: <ph.Permission>[ph.Permission.microphone],
      title: 'الميكروفون',
      message: 'نحتاج الميكروفون لإجراء المكالمات الصوتية',
      icon: Icons.mic,
    );
    if (!granted || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudioCallScreen(peer: widget.peer, isCaller: true),
      ),
    );
  }

  Future<void> _startVideoCall() async {
    final granted = await PermissionDialog.ensure(
      context,
      permissions: <ph.Permission>[
        ph.Permission.microphone,
        ph.Permission.camera,
      ],
      title: 'الكاميرا والميكروفون',
      message: 'نحتاجهما لإجراء مكالمات الفيديو',
      icon: Icons.videocam,
    );
    if (!granted || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(peer: widget.peer, isCaller: true),
      ),
    );
  }

  // ============================================
  // === الواجهة ===
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final peerOnline = context.select<DeviceDiscovery, bool>(
      (d) => d.isDeviceOnline(widget.peer.deviceId),
    );

    return Scaffold(
      appBar: _isSearching
          ? _buildSearchAppBar(isDark)
          : _buildNormalAppBar(isDark, peerOnline),
      body: Column(
        children: [
          if (_pinnedMessages.isNotEmpty &&
              !_isSearching &&
              _replyToMessage == null)
            _buildPinnedBar(isDark),

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.darkBackground
                    : const Color(0xFFECE5DD),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredMessages.isEmpty
                      ? (_searchQuery.isNotEmpty
                          ? _buildNoResultsState(isDark)
                          : _buildEmptyState(isDark))
                      : _buildMessagesList(isDark),
            ),
          ),
          if (_replyToMessage != null && !_isRecording)
            _buildReplyBar(isDark),
          if (_multiSendProgress != null) _buildMultiSendProgressBar(isDark),
          if (!_isSearching) ...[
            if (_isRecording)
              _buildRecordingBar(isDark)
            else
              _buildInputBar(isDark, peerOnline),
          ],
        ],
      ),
    );
  }

  // ============================================
  // === شريط التقدّم المتعدد ===
  // ============================================

  Widget _buildMultiSendProgressBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.08),
        border: Border(
          top: BorderSide(
            color: AppTheme.primaryColor.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _multiSendProgress ?? 'جارٍ الإرسال...',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // === شريط المثبتات ===
  // ============================================

  Widget _buildPinnedBar(bool isDark) {
    if (_pinnedMessages.isEmpty) return const SizedBox.shrink();

    final current = _pinnedMessages[_currentPinnedIndex];
    final preview = _pinnedPreviewText(current);
    final senderName = (current['is_outgoing'] == 1)
        ? 'أنت'
        : widget.peer.name;
    final total = _pinnedMessages.length;
    final position = _currentPinnedIndex + 1;

    return Material(
      color: AppTheme.primaryColor.withOpacity(isDark ? 0.15 : 0.08),
      child: InkWell(
        onTap: _nextPinnedMessage,
        onLongPress: _showAllPinned,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: AppTheme.primaryColor,
                width: 3,
              ),
              bottom: BorderSide(
                color: isDark
                    ? AppTheme.darkDivider
                    : AppTheme.lightDivider,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.push_pin,
                size: 18,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'رسالة مثبتة',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        if (total > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$position/$total',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$senderName: $preview',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _unpinCurrent,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _pinnedPreviewText(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    switch (type) {
      case AppConstants.mediaText:
        return (message['body'] as String?) ?? '';
      case AppConstants.mediaImage:
        return '📷 صورة';
      case AppConstants.mediaVideo:
        return '🎥 فيديو';
      case AppConstants.mediaAudio:
        return '🎵 مقطع صوتي';
      case AppConstants.mediaFile:
        return '📎 ${message['file_name'] ?? 'ملف'}';
      default:
        return 'رسالة';
    }
  }

  // ============================================
  // === AppBar ===
  // ============================================

  PreferredSizeWidget _buildNormalAppBar(bool isDark, bool peerOnline) {
    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          _Avatar(name: widget.peer.name, online: peerOnline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.peer.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.peer.hasValidNumber) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${widget.peer.number}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  peerOnline
                      ? 'متصل الآن'
                      : 'غير متصل • آخر ظهور ${_formatLastSeen(widget.peer.lastSeen)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'بحث',
          onPressed: _enterSearchMode,
        ),
        IconButton(
          icon: const Icon(Icons.call_outlined),
          tooltip: 'مكالمة صوتية',
          onPressed: peerOnline ? _startAudioCall : null,
        ),
        IconButton(
          icon: const Icon(Icons.videocam_outlined),
          tooltip: 'مكالمة فيديو',
          onPressed: peerOnline ? _startVideoCall : null,
        ),
        PopupMenuButton<String>(
          onSelected: (v) {},
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'clear',
              child: Text('مسح المحادثة'),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSearchAppBar(bool isDark) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _exitSearchMode,
      ),
      titleSpacing: 0,
      title: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          hintText: 'ابحث في الرسائل...',
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
        if (_searchQuery.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${_filteredMessages.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (_searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'مسح',
            onPressed: () => _searchController.clear(),
          ),
      ],
    );
  }

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
              'لم يتم العثور على رسائل تحتوي على "$_searchQuery"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textColor),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // === شريط التسجيل ===
  // ============================================

  Widget _buildRecordingBar(bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: AppTheme.errorColor,
              tooltip: 'إلغاء',
              onPressed: _cancelRecording,
            ),
            _PulsingDot(color: AppTheme.errorColor),
            const SizedBox(width: 10),
            Text(
              _formatRecordingDuration(_recordingSeconds),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _WaveformBars(
                values: _waveform,
                color: AppTheme.errorColor.withOpacity(0.7),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppTheme.primaryColor,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _stopAndSendRecording,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRecordingDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ============================================
  // === شريط الإدخال ===
  // ============================================

  Widget _buildInputBar(bool isDark, bool peerOnline) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: _isSendingMedia
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle_outline),
              color: AppTheme.primaryColor,
              onPressed:
                  (peerOnline && !_isSendingMedia) ? _showAttachMenu : null,
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.darkBackground
                      : const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocus,
                  enabled: peerOnline,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: _multiSendProgress ??
                        (peerOnline ? 'اكتب رسالة...' : 'الجهاز غير متصل'),
                    hintStyle: TextStyle(
                      color: _multiSendProgress != null
                          ? AppTheme.primaryColor
                          : (isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary),
                      fontSize: 15,
                      fontWeight: _multiSendProgress != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (_canSend && peerOnline)
              Material(
                color: AppTheme.primaryColor,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _sendText,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.send, color: Colors.white, size: 22),
                  ),
                ),
              )
            else
              Material(
                color: peerOnline
                    ? AppTheme.primaryColor
                    : AppTheme.primaryColor.withOpacity(0.35),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: peerOnline ? _startRecording : null,
                  onLongPress: peerOnline ? _startRecording : null,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.mic, color: Colors.white, size: 22),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // === قائمة الرسائل ===
  // ============================================

  Widget _buildMessagesList(bool isDark) {
    final items = _filteredMessages.reversed.toList();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final msg = items[index];
        final prev = index > 0 ? items[index - 1] : null;
        final showDate = _searchQuery.isEmpty && _shouldShowDate(msg, prev);
        final isHighlighted = _highlightedMessageId == msg['message_id'];
        final isPinned = (msg['is_pinned'] as int?) == 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDate) _buildDateDivider(msg['created_at'] as int, isDark),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: isHighlighted
                  ? BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: _MessageBubble(
                message: msg,
                isDark: isDark,
                searchQuery: _searchQuery,
                isPinned: isPinned,
                onReply: () => _startReply(msg),
                onLongPress: () => _showMessageOptions(msg),
                onOpenImage: _openImage,
                onOpenVideo: _openVideo,
                onOpenFile: _openFile,
                transfers: _messageService?.transfers ?? const {},
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 72,
              color: AppTheme.primaryColor.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد رسائل بعد',
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
              'ابدأ بإرسال رسالة إلى ${widget.peer.name}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowDate(
    Map<String, dynamic> msg,
    Map<String, dynamic>? prev,
  ) {
    if (prev == null) return true;
    final t1 = msg['created_at'] as int;
    final t2 = prev['created_at'] as int;
    final d1 = DateTime.fromMillisecondsSinceEpoch(t1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(t2);
    return d1.day != d2.day || d1.month != d2.month || d1.year != d2.year;
  }

  Widget _buildDateDivider(int timestamp, bool isDark) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withOpacity(0.35)
                : Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _formatDate(date),
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyBar(bool isDark) {
    final msg = _replyToMessage!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (msg['is_outgoing'] == 1) ? 'أنت' : widget.peer.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _previewText(msg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.darkSurface
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _attachOption(
                    icon: Icons.image_outlined,
                    label: 'صور',
                    color: Colors.purple,
                    onTap: () {
                      Navigator.pop(context);
                      _pickAndSendMedia(AppConstants.mediaImage);
                    },
                  ),
                  _attachOption(
                    icon: Icons.videocam_outlined,
                    label: 'فيديو',
                    color: Colors.red,
                    onTap: () {
                      Navigator.pop(context);
                      _pickAndSendMedia(AppConstants.mediaVideo);
                    },
                  ),
                  _attachOption(
                    icon: Icons.insert_drive_file_outlined,
                    label: 'ملف',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pop(context);
                      _pickAndSendMedia(AppConstants.mediaFile);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'يمكنك اختيار عدة صور دفعة واحدة',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  String _previewText(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    switch (type) {
      case AppConstants.mediaText:
        return (msg['body'] as String?) ?? '';
      case AppConstants.mediaImage:
        return '📷 صورة';
      case AppConstants.mediaVideo:
        return '🎥 فيديو';
      case AppConstants.mediaAudio:
        return '🎵 مقطع صوتي';
      case AppConstants.mediaFile:
        return '📎 ملف';
      default:
        return 'رسالة';
    }
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    if (diff < 7) return 'منذ $diff أيام';
    return DateFormat('d MMM yyyy', 'ar').format(d);
  }

  String _formatLastSeen(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'قبل لحظات';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    return 'قبل ${diff.inDays} يوم';
  }
}

// ============================================================
// === قائمة كل المثبتات ===
// ============================================================
class _PinnedMessagesSheet extends StatelessWidget {
  final List<Map<String, dynamic>> pinnedMessages;
  final int currentIndex;
  final void Function(int index, String messageId) onSelect;
  final void Function(Map<String, dynamic> message) onUnpin;

  const _PinnedMessagesSheet({
    required this.pinnedMessages,
    required this.currentIndex,
    required this.onSelect,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(
                  Icons.push_pin,
                  size: 20,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'الرسائل المثبتة (${pinnedMessages.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: pinnedMessages.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: isDark
                    ? AppTheme.darkDivider
                    : AppTheme.lightDivider,
              ),
              itemBuilder: (context, index) {
                final message = pinnedMessages[index];
                final isCurrent = index == currentIndex;

                return _PinnedMessageTile(
                  message: message,
                  index: index,
                  isCurrent: isCurrent,
                  isDark: isDark,
                  onTap: () => onSelect(
                    index,
                    message['message_id'] as String,
                  ),
                  onUnpin: () => onUnpin(message),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedMessageTile extends StatelessWidget {
  final Map<String, dynamic> message;
  final int index;
  final bool isCurrent;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onUnpin;

  const _PinnedMessageTile({
    required this.message,
    required this.index,
    required this.isCurrent,
    required this.isDark,
    required this.onTap,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final type = message['type'] as String?;
    final body = message['body'] as String? ?? '';
    final fileName = message['file_name'] as String?;
    final createdAt = message['created_at'] as int;
    final isOutgoing = (message['is_outgoing'] as int?) == 1;

    return Material(
      color: isCurrent
          ? AppTheme.primaryColor.withOpacity(0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _iconForType(type),
                          size: 12,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isOutgoing ? 'أنت' : 'الطرف الآخر',
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
                    const SizedBox(height: 4),
                    Text(
                      type == AppConstants.mediaText
                          ? body
                          : (fileName ?? _mediaLabel(type)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onUnpin,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.push_pin,
                      size: 18,
                      color: AppTheme.primaryColor.withOpacity(0.6),
                    ),
                  ),
                ),
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

  String _formatTime(int timestamp) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    if (diff < 7) return 'منذ $diff أيام';
    return DateFormat('d/M/yyyy', 'ar').format(d);
  }
}

// ============================================================
// === عناصر مساعدة ===
// ============================================================

class _OptionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _OptionItem({
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

class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.4 + _c.value * 0.6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  final List<double> values;
  final Color color;

  const _WaveformBars({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Container(
        height: 28,
        alignment: Alignment.center,
        child: Text(
          '● ● ●',
          style: TextStyle(color: color, fontSize: 10),
        ),
      );
    }
    return SizedBox(
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: values.map((v) {
          return Container(
            width: 3,
            height: 6 + (v * 22),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool online;

  const _Avatar({required this.name, required this.online});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: online ? AppTheme.successColor : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isDark;
  final String searchQuery;
  final bool isPinned;
  final VoidCallback onReply;
  final VoidCallback onLongPress;
  final void Function(String) onOpenImage;
  final void Function(String, {String? title}) onOpenVideo;
  final Future<void> Function(String) onOpenFile;
  final Map<String, double> transfers;

  const _MessageBubble({
    required this.message,
    required this.isDark,
    required this.searchQuery,
    required this.isPinned,
    required this.onReply,
    required this.onLongPress,
    required this.onOpenImage,
    required this.onOpenVideo,
    required this.onOpenFile,
    required this.transfers,
  });

  @override
  Widget build(BuildContext context) {
    final isOutgoing = (message['is_outgoing'] as int?) == 1;
    final messageId = message['message_id'] as String;
    final isAudio = (message['type'] as String?) == AppConstants.mediaAudio;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isOutgoing
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: GestureDetector(
          onLongPress: onLongPress,
          onDoubleTap: onReply,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isAudio
                  ? 320
                  : MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: isOutgoing
                  ? (isDark
                      ? AppTheme.darkOutgoingBubble
                      : AppTheme.lightOutgoingBubble)
                  : (isDark
                      ? AppTheme.darkIncomingBubble
                      : AppTheme.lightIncomingBubble),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isOutgoing ? 14 : 3),
                bottomRight: Radius.circular(isOutgoing ? 3 : 14),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
              border: isPinned
                  ? Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.5),
                      width: 1.5,
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isPinned)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 6,
                      left: 10,
                      right: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.push_pin,
                          size: 12,
                          color: AppTheme.primaryColor.withOpacity(0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'مثبتة',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),

                _buildContent(context, isDark),

                if (transfers.containsKey(messageId))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: transfers[messageId],
                        minHeight: 3,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 10,
                    right: 10,
                    bottom: 5,
                    top: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(
                          DateTime.fromMillisecondsSinceEpoch(
                            message['created_at'] as int,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white.withOpacity(0.7)
                              : Colors.black.withOpacity(0.5),
                        ),
                      ),
                      if (isOutgoing) ...[
                        const SizedBox(width: 4),
                        _statusIcon(message['status'] as String?),
                      ],
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

  Widget _buildContent(BuildContext context, bool isDark) {
    final type = message['type'] as String?;
    final filePath = message['file_path'] as String?;
    final isOutgoing = (message['is_outgoing'] as int?) == 1;

    switch (type) {
      case AppConstants.mediaImage:
        return _buildImagePreview(filePath);
      case AppConstants.mediaVideo:
        return _buildVideoPreview(filePath);
      case AppConstants.mediaAudio:
        if (filePath == null || !File(filePath).existsSync()) {
          return _buildPlaceholderPreview(
            icon: Icons.mic_off,
            label: 'مقطع صوتي غير متوفر',
            color: Colors.grey,
          );
        }
        return VoiceMessageBubble(
          filePath: filePath,
          durationMs: message['duration_ms'] as int?,
          isOutgoing: isOutgoing,
          isDark: isDark,
        );
      case AppConstants.mediaFile:
        final fileName = message['file_name'] as String? ?? 'ملف';
        return _buildFilePreview(filePath, fileName);
      case AppConstants.mediaText:
      default:
        final body = message['body'] as String? ?? '';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _buildHighlightedText(body, isDark: isDark),
        );
    }
  }

  Widget _buildHighlightedText(String text, {required bool isDark}) {
    final baseStyle = TextStyle(
      fontSize: 15,
      height: 1.35,
      color:
          isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
    );

    if (searchQuery.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = searchQuery.toLowerCase();
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
        text: text.substring(index, index + searchQuery.length),
        style: TextStyle(
          backgroundColor: Colors.yellow.withOpacity(0.6),
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = index + searchQuery.length;
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  Widget _buildImagePreview(String? filePath) {
    if (filePath == null || !File(filePath).existsSync()) {
      return _buildPlaceholderPreview(
        icon: Icons.broken_image_outlined,
        label: 'صورة غير متوفرة',
        color: Colors.grey,
      );
    }
    return GestureDetector(
      onTap: () => onOpenImage(filePath),
      child: Hero(
        tag: 'image_$filePath',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 260,
              maxHeight: 320,
              minWidth: 140,
              minHeight: 100,
            ),
            child: Image.file(
              File(filePath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildPlaceholderPreview(
                icon: Icons.broken_image_outlined,
                label: 'تعذّر فتح الصورة',
                color: Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPreview(String? filePath) {
    final exists = filePath != null && File(filePath).existsSync();
    return GestureDetector(
      onTap: exists ? () => onOpenVideo(filePath) : null,
      child: Container(
        width: 240,
        height: 160,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.movie_outlined,
              size: 60,
              color: Colors.white.withOpacity(0.15),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: exists
                    ? Colors.white.withOpacity(0.95)
                    : Colors.white.withOpacity(0.3),
                shape: BoxShape.circle,
                boxShadow: exists
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 38,
                color: exists
                    ? AppTheme.primaryColor
                    : Colors.white.withOpacity(0.5),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      exists ? 'فيديو' : 'غير متوفر',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePreview(String? filePath, String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : 'FILE';
    final exists = filePath != null && File(filePath).existsSync();

    Color iconColor = AppTheme.primaryColor;
    if (['PDF'].contains(ext)) iconColor = Colors.red;
    if (['DOC', 'DOCX'].contains(ext)) iconColor = Colors.blue;
    if (['XLS', 'XLSX'].contains(ext)) iconColor = Colors.green;
    if (['ZIP', 'RAR'].contains(ext)) iconColor = Colors.orange;

    return GestureDetector(
      onTap: exists ? () => onOpenFile(filePath) : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                ext.length > 4 ? ext.substring(0, 4) : ext,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    exists ? 'اضغط للفتح' : 'غير متوفر',
                    style: TextStyle(
                      fontSize: 11,
                      color: exists
                          ? Colors.grey.shade600
                          : AppTheme.errorColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderPreview({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      width: 200,
      height: 80,
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: color),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(String? status) {
    switch (status) {
      case 'pending':
        return const Icon(Icons.schedule, size: 14, color: Colors.grey);
      case 'sent':
        return const Icon(Icons.check, size: 15, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 15, color: Colors.grey);
      case 'read':
        return const Icon(
          Icons.done_all,
          size: 15,
          color: Color(0xFF4FC3F7),
        );
      case 'failed':
        return const Icon(
          Icons.error_outline,
          size: 14,
          color: AppTheme.errorColor,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  String _formatTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _ImageViewerScreen extends StatelessWidget {
  final String filePath;

  const _ImageViewerScreen({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                child: Center(
                  child: Hero(
                    tag: 'image_$filePath',
                    child: Image.file(
                      File(filePath),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 64,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
