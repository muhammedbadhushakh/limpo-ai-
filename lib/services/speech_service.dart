// speech_service.dart
//
// NOTE: This class is NO LONGER USED directly by background_service.dart.
// SpeechToText is now created and owned inside LimpoTaskHandler (background
// isolate) so it survives app close. This file is kept for any future use
// (e.g. one-shot STT from the UI) but is not part of the wake-word loop.
//
// If you were importing this from background_service.dart — don't. Use the
// _speech instance inside LimpoTaskHandler instead.

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (e) {
        debugPrint('STT ERROR: ${e.errorMsg} permanent=${e.permanent}');
        if (e.permanent) _initialized = false;
      },
      // FIX: use onStatus for instant end-of-session detection
      // instead of the old 300 ms polling loop (which was racy and slow).
      onStatus: (status) {
        debugPrint('STT STATUS: $status');
      },
    );
    return _initialized;
  }

  Future<void> startListening(
      void Function(String) onResult, {
        void Function()? onDone,
        bool partial = true,
        ListenMode listenMode = ListenMode.dictation,
        Duration pauseFor = const Duration(seconds: 5),
        Duration listenFor = const Duration(seconds: 30),
      }) async {
    final available = await _ensureInitialized();
    if (!available) {
      onDone?.call();
      return;
    }

    if (_speech.isListening) {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords;
        if (words.isEmpty) return;
        if (partial || result.finalResult) onResult(words);
      },
      listenFor: listenFor,
      pauseFor: pauseFor,
      partialResults: partial,
      cancelOnError: false,
      listenMode: listenMode,
    );

    // FIX: replaced 300 ms polling loop with a clean status-driven wait.
    // The onStatus callback above already fires 'done'/'notListening' the
    // moment the session ends — no need to poll.
    if (onDone != null) {
      Future(() async {
        // Wait for session to actually start first
        await Future.delayed(const Duration(milliseconds: 300));
        // Then wait for it to end
        while (_speech.isListening) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
        onDone();
      });
    }
  }

  Future<void> stopListening() async {
    if (_speech.isListening) await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}