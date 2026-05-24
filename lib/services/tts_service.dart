// import 'dart:async';
// import 'package:flutter_tts/flutter_tts.dart';
//
// class TTSService {
//   final FlutterTts _tts = FlutterTts();
//   bool _initialized = false;
//
//   Future<void> init() async {
//     if (_initialized) return;
//     await _tts.setLanguage("en-US");
//     await _tts.setSpeechRate(0.5);
//     await _tts.setVolume(1.0);
//     await _tts.setPitch(1.0);
//     _initialized = true;
//   }
//
//   /// Speaks [text] and waits until TTS finishes before returning.
//   Future<void> speak(String text) async {
//     if (!_initialized) await init();
//
//     // Stop any in-progress speech first to prevent overlap.
//     await _tts.stop();
//
//     final completer = Completer<void>();
//
//     _tts.setCompletionHandler(() {
//       if (!completer.isCompleted) completer.complete();
//     });
//
//     _tts.setCancelHandler(() {
//       if (!completer.isCompleted) completer.complete();
//     });
//
//     _tts.setErrorHandler((msg) {
//       if (!completer.isCompleted) completer.complete();
//     });
//
//     await _tts.speak(text);
//
//     // Wait for speech to finish (with a safety timeout).
//     await completer.future.timeout(
//       Duration(seconds: (text.length / 10).ceil().clamp(3, 30)),
//       onTimeout: () {},
//     );
//   }
//
//   Future<void> stop() async {
//     await _tts.stop();
//   }
// }