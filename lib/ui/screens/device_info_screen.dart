import 'package:flutter/material.dart';
import 'package:lanphone.app/ui/screens/notification_settings_screen.dart';

class DeviceInfoScreen extends StatefulWidget {
  final dynamic device;

  const DeviceInfoScreen({super.key, this.device});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('معلومات الجهاز'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            Text('معلومات الجهاز: ${widget.device ?? "غير معروف"}'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // تم إزالة معامل device المسبب للخطأ
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationSettingsScreen(),
                  ),
                );
              },
              child: const Text('إعدادات الإشعارات'),
            ),
          ],
        ),
      ),
    );
  }
}
