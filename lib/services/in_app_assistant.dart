// in_app_assistant.dart
//
// Runs the full wake → listen → process → speak pipeline INSIDE the app,
// with no background service. The mic opens ONCE per tap, stays open until
// the user finishes speaking, processes the command, then closes cleanly.
//
// This avoids the constant on/off cycling of the background wake-word loop
// and works reliably even without foreground service permissions.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'command_service.dart';
import '../utils/constants.dart';

/// Callback fired whenever the assistant state or spoken text changes.
typedef StateCallback    = void Function(AssistantState state);
typedef TextCallback     = void Function(String text);

class InAppAssistant {
  // ── STT / TTS / Command ──────────────────────────────────────────────────
  final _speech = SpeechToText();
  final _tts    = FlutterTts();
  final _cmd    = CommandService();

  bool _sttReady = false;
  bool _ttsReady = false;

  // ── Public state streams ─────────────────────────────────────────────────
  final _stateCtrl = StreamController<AssistantState>.broadcast();
  final _textCtrl  = StreamController<String>.broadcast();
  final _replyCtrl = StreamController<String>.broadcast();

  Stream<AssistantState> get onStateChanged => _stateCtrl.stream;
  Stream<String>         get onTextChanged  => _textCtrl.stream;
  Stream<String>         get onReply        => _replyCtrl.stream;

  AssistantState _currentState = AssistantState.idle;
  bool           _busy         = false;

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await _initTts();
    await _initStt();
  }

  Future<void> _initTts() async {
    if (_ttsReady) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ttsReady = true;
    debugPrint('IN-APP: TTS ready');
  }

  Future<void> _initStt() async {
    if (_sttReady) return;
    _sttReady = await _speech.initialize(
      onError: (e) => debugPrint('IN-APP STT ERROR: ${e.errorMsg}'),
      onStatus: (s) => debugPrint('IN-APP STT STATUS: $s'),
    );
    debugPrint('IN-APP: STT ready=$_sttReady');
  }

  // ── Public entry point ───────────────────────────────────────────────────

  /// Call this when the user taps the in-app mic button.
  /// Runs: speak "Yes?" → listen for command → process → speak reply.
  /// Safe to call repeatedly — ignores taps while already busy.
  Future<void> trigger() async {
    if (_busy) return;
    _busy = true;

    try {
      await _initTts();
      await _initStt();

      if (!_sttReady) {
        await _speak("Sorry, microphone isn't available.");
        return;
      }

      // 1. Acknowledge
      _setState(AssistantState.wakeWord);
      await _speak('Yes?');

      // 2. Listen
      _setState(AssistantState.listening);
      final command = await _listenOnce();

      if (command.isEmpty) {
        _setState(AssistantState.idle);
        _busy = false;
        return;
      }

      _textCtrl.add(command);

      // 3. Process
      _setState(AssistantState.processing);
      String reply;
      try {
        reply = await _cmd.handleCommand(command);
      } catch (e) {
        reply = 'Sorry, something went wrong.';
        debugPrint('IN-APP CMD ERROR: $e');
      }

      // 4. Speak reply
      _replyCtrl.add(reply);
      await _speak(reply);

    } finally {
      _setState(AssistantState.idle);
      _busy = false;
    }
  }

  bool get isBusy => _busy;

  // ── Single-shot listen ───────────────────────────────────────────────────
  //
  // Opens the mic ONCE, waits until the user stops talking (pauseFor = 3 s)
  // or the hard limit (listenFor = 20 s) is hit, then returns the transcript.
  // No looping, no cycling — one open, one close.

  Future<String> _listenOnce() async {
    String result = '';
    final completer = Completer<String>();

    _speech.listen(
      onResult: (r) {
        final words = r.recognizedWords.trim();
        if (words.isNotEmpty) {
          result = words;
          debugPrint('IN-APP HEARD: "$words"');
          _textCtrl.add(words);
          // Return as soon as we get a final result — no need to wait for
          // the full pauseFor timeout.
          if (r.finalResult && !completer.isCompleted) {
            completer.complete(result);
          }
        }
      },
      listenFor: const Duration(seconds: 20),
      // 3 s silence ends the session — feels natural for commands
      pauseFor:  const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: false,
      listenMode: ListenMode.dictation,
    );

    // Also complete when STT session ends naturally (status = done/notListening)
    // so we don't hang if the user says nothing.
    _speech.statusListener = (status) {
      debugPrint('IN-APP STATUS: $status');
      if ((status == 'done' || status == 'notListening') &&
          !completer.isCompleted) {
        completer.complete(result);
      }
    };

    // Safety timeout — in case STT goes silent and never fires done
    return completer.future.timeout(
      const Duration(seconds: 22),
      onTimeout: () => result,
    );
  }

  // ── TTS helper ───────────────────────────────────────────────────────────

  Future<void> _speak(String text) async {
    _setState(AssistantState.speaking);
    await _tts.stop();

    final completer = Completer<void>();
    _tts.setCompletionHandler(() { if (!completer.isCompleted) completer.complete(); });
    _tts.setCancelHandler(()    { if (!completer.isCompleted) completer.complete(); });
    _tts.setErrorHandler((_)    { if (!completer.isCompleted) completer.complete(); });

    await _tts.speak(text);

    await completer.future.timeout(
      Duration(seconds: (text.length / 8).ceil().clamp(3, 30)),
      onTimeout: () {},
    );

    // Small gap so mic doesn't pick up TTS audio tail
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _setState(AssistantState s) {
    _currentState = s;
    _stateCtrl.add(s);
  }

  Future<void> dispose() async {
    await _speech.stop();
    await _tts.stop();
    await _stateCtrl.close();
    await _textCtrl.close();
    await _replyCtrl.close();
  }
}