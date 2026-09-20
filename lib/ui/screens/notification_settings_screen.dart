import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/ringtone_service.dart';
import '../theme/app_theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _enableNotifications = true;
  bool _enableSound = true;
  bool _enableVibration = true;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enableNotifications = prefs.getBool('notif_enabled') ?? true;
      _enableSound = prefs.getBool('notif_sound') ?? true;
      _enableVibration = prefs.getBool('notif_vibrate') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_enabled', _enableNotifications);
    await prefs.setBool('notif_sound', _enableSound);
    await prefs.setBool('notif_vibrate', _enableVibration);
    _isDirty = false;
  }

  void _markDirty() {
    if (!_isDirty) {
      setState(() {
        _isDirty = true;
      });
    }
  }

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('حفظ التغييرات؟'),
        content: const Text('لقد قمت بتعديل إعدادات الإشعارات. هل تريد حفظها قبل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تجاهل'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('حفظ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true) {
      await _saveSettings();
      return true;
    } else if (result == false) {
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ringtoneService = context.watch<RingtoneService>();

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعدادات الإشعارات والتنبيهات'),
          actions: [
            if (_isDirty)
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: () async {
                  await _saveSettings();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم حفظ الإعدادات')),
                    );
                    Navigator.pop(context);
                  }
                },
              ),
          ],
        ),
        body: ListView(
          children: [
            SwitchListTile(
              title: const Text('تفعيل الإشعارات'),
              subtitle: const Text('استلام التنبيهات للرسائل والمكالمات الواردة'),
              value: _enableNotifications,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) {
                setState(() => _enableNotifications = val);
                _markDirty();
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('الأصوات'),
              subtitle: const Text('تشغيل صوت عند وصول رسالة جديدة'),
              value: _enableSound,
              enabled: _enableNotifications,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) {
                setState(() => _enableSound = val);
                _markDirty();
              },
            ),
            SwitchListTile(
              title: const Text('الاهتزاز'),
              subtitle: const Text('اهتزاز الجهاز عند وصول التنبيهات'),
              value: _enableVibration,
              enabled: _enableNotifications,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) {
                setState(() => _enableVibration = val);
                _markDirty();
              },
            ),
            const Divider(),
            ListTile(
              enabled: _enableNotifications && _enableSound,
              title: const Text('نغمة الاتصال'),
              subtitle: Text(ringtoneService.currentRingtoneName),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
              },
            ),
          ],
        ),
      ),
    );
  }
}
