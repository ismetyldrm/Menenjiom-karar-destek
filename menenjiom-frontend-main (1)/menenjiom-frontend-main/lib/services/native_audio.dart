import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class NativeAudio {
  // C++ koduna yazdığımız kanalın birebir aynısı
  static const MethodChannel _channel = MethodChannel(
    'com.menenjiom.app/audio',
  );

  static Future<void> startRecording() async {
    await _channel.invokeMethod('startRecording');
  }

  static Future<String?> stopRecording() async {
    final dir = await getTemporaryDirectory();
    final filePath =
        '${dir.path}\\dr_voice_${DateTime.now().millisecondsSinceEpoch}.wav';

    final result = await _channel.invokeMethod('stopRecording', {
      'path': filePath,
    });
    return result as String?;
  }

  // --- EKLENEN YENİ OYNATMA VE DURDURMA KOMUTLARI ---
  static Future<void> playAudio(String path) async {
    await _channel.invokeMethod('playAudio', {'path': path});
  }

  static Future<void> stopAudio() async {
    await _channel.invokeMethod('stopAudio');
  }
}
