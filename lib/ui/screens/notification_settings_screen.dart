import 'package:flutter/material.dart';
import 'package:lanphone.app/core/services/ringtone_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _enableNotifications = true;
  final RingtoneService ringtoneService = RingtoneService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات الإشعارات'),
      ),
      body: ListView(
        children: [
          // السطر 134: تم استخدام value بدلاً من enabled
          SwitchListTile(
            title: const Text('تفعيل إشعارات التطبيق'),
            value: _enableNotifications,
            onChanged: (bool value) {
              setState(() {
                _enableNotifications = value;
              });
            },
          ),
          // السطر 145: تم استخدام value بدلاً من enabled
          SwitchListTile(
            title: const Text('تفعيل الأصوات'),
            value: _enableNotifications,
            onChanged: (bool value) {
              setState(() {
                _enableNotifications = value;
              });
            },
          ),
          ListTile(
            title: const Text('نغمة الرنين الحالية'),
            subtitle: Text(ringtoneService.currentRingtoneName),
          ),
        ],
      ),
    );
  }
}
