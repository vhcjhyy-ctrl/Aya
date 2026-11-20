import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/core/adhan_native_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.adhan.app/alarm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('schedulePrayerAlarm forwards the explicit test sound override', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return true;
    });

    await AdhanNativeController.instance.schedulePrayerAlarm(
      id: 9999,
      time: DateTime(2026, 11, 20, 12),
      mp3ResName: 'adhan_meshary_al_fasy_kuwait',
      prayerName: 'Dhuhr',
      forceSound: true,
    );

    expect(receivedCall?.method, 'scheduleExactAlarm');
    expect(
      (receivedCall?.arguments as Map<dynamic, dynamic>)['forceSound'],
      isTrue,
    );
  });

  test('normal prayer alarms do not force audio by default', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return true;
    });

    await AdhanNativeController.instance.schedulePrayerAlarm(
      id: 1,
      time: DateTime(2026, 11, 20, 12),
      mp3ResName: 'adhan_meshary_al_fasy_kuwait',
      prayerName: 'Dhuhr',
    );

    expect(
      (receivedCall?.arguments as Map<dynamic, dynamic>)['forceSound'],
      isFalse,
    );
  });
}
