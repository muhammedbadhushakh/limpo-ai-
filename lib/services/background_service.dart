// background_service.dart

import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'command_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC API  (main isolate)
// ─────────────────────────────────────────────────────────────────────────────

class LimpoBackgroundService {

  static void initialize() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'limpo_channel',
        channelName: 'Limpo Assistant',
        channelDescription: 'Limpo AI is listening',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Watchdog fires every 2 s — only used to catch total crashes.
        // Normal session cycling is handled by _onSessionEnded().
        eventAction: ForegroundTaskEventAction.repeat(2000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start() async {
    debugPrint('LIMPO: start()');
    if (await FlutterForegroundTask.isRunningService) {
      debugPrint('LIMPO: already running — restarting STT');
      FlutterForegroundTask.sendDataToTask('restart');
      return;
    }
    await FlutterForegroundTask.startService(
      notificationTitle: 'Limpo AI',
      notificationText: 'Say "Hey Limpo"',
      callback: startCallback,
    );
  }

  static Future<void> stop() async {
    FlutterForegroundTask.sendDataToTask('stop');
    await Future.delayed(const Duration(milliseconds: 400));
    await FlutterForegroundTask.stopService();
  }

  static Future<void> triggerManually() async {
    FlutterForegroundTask.sendDataToTask('manual_trigger');
  }

  static Future<bool> get isRunning async =>
      FlutterForegroundTask.isRunningService;
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void startCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(LimpoTaskHandler());
}

// ─────────────────────────────────────────────────────────────────────────────
// TASK HANDLER
// ─────────────────────────────────────────────────────────────────────────────

class LimpoTaskHandler extends TaskHandler {

  FlutterTts?     _tts;
  SpeechToText?   _speech;
  CommandService? _cmd;

  bool _sttReady    = false;
  bool _isProcessing = false;  // true while in command mode (wake→TTS→STT→reply)
  bool _stopped      = false;

  // Single mutex flag — prevents any double-start race condition.
  // Set true synchronously before any async work, cleared when session ends.
  bool _sessionActive = false;

  String _latestText = '';

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('LIMPO TASK: onStart');
    _tts    = FlutterTts();
    _speech = SpeechToText();
    _cmd    = CommandService();
    await _initTts();
    await _initStt();
    _startWakeSession();
  }

  // Watchdog — only fires if STT completely stopped with no self-restart
  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_stopped || _isProcessing) return;
    final listening = _speech?.isListening ?? false;
    if (!listening && !_sessionActive) {
      debugPrint('LIMPO WATCHDOG: dead — restarting');
      _startWakeSession();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _stopped = true;
    await _speech?.stop();
    await _tts?.stop();
  }

  @override
  void onReceiveData(Object data) {
    final msg = data.toString();
    debugPrint('LIMPO TASK ← $msg');
    switch (msg) {
      case 'restart':
        _stopped = false;
        _isProcessing = false;
        _sessionActive = false;
        _speech?.stop();
        Future.delayed(const Duration(milliseconds: 300), _startWakeSession);
        break;
      case 'stop':
        _stopped = true;
        _sessionActive = false;
        _speech?.stop();
        _tts?.stop();
        break;
      case 'manual_trigger':
        if (!_isProcessing) {
          _isProcessing = true;
          _sessionActive = false;
          _speech?.stop();
          // Small delay so stop() completes before we start command mode
          Future.delayed(const Duration(milliseconds: 300), _onWakeDetected);
        }
        break;
    }
  }

  // ── TTS ─────────────────────────────────────────────────────────────────────

  Future<void> _initTts() async {
    await _tts!.setLanguage('en-US');
    await _tts!.setSpeechRate(0.5);
    await _tts!.setVolume(1.0);
    await _tts!.setPitch(1.0);
    debugPrint('LIMPO TASK: TTS ready');
  }

  Future<void> _speak(String text) async {
    _sendState('speaking');
    _notify(text);

    final completer = Completer<void>();
    _tts!.setCompletionHandler(() { if (!completer.isCompleted) completer.complete(); });
    _tts!.setCancelHandler(()    { if (!completer.isCompleted) completer.complete(); });
    _tts!.setErrorHandler((_)    { if (!completer.isCompleted) completer.complete(); });

    await _tts!.stop();
    await _tts!.speak(text);

    await completer.future.timeout(
      Duration(seconds: (text.length / 8).ceil().clamp(3, 30)),
      onTimeout: () {},
    );

    // Gap between TTS ending and mic opening — prevents STT picking up
    // the tail of the TTS audio as the user's command.
    await Future.delayed(const Duration(milliseconds: 700));
  }

  // ── STT init ────────────────────────────────────────────────────────────────

  Future<void> _initStt() async {
    if (_sttReady) return;
    debugPrint('LIMPO TASK: initializing STT');
    _sttReady = await _speech!.initialize(
      onError: (e) {
        debugPrint('LIMPO STT ERROR: ${e.errorMsg}');
        // Only truly unrecoverable errors clear _sttReady.
        // speech_timeout and no_match are normal — do NOT re-init on those.
        if (e.errorMsg == 'error_client' || e.errorMsg == 'error_permission') {
          _sttReady = false;
        }
        _sessionActive = false;
        // If not in command mode, self-restart immediately
        if (!_isProcessing && !_stopped) {
          Future.delayed(const Duration(milliseconds: 500), _startWakeSession);
        }
      },
      onStatus: (status) {
        debugPrint('LIMPO STT STATUS: $status');
        // 'done' means the current session ended naturally (pauseFor timeout,
        // listenFor timeout, or we called stop()). This is the normal path.
        // We do NOT restart here — _startWakeSession handles the restart
        // after checking _isProcessing, so there's no race.
        if (status == 'done' || status == 'notListening') {
          _sessionActive = false;
          if (!_isProcessing && !_stopped) {
            // Self-restart: the session ended, immediately open a new one.
            // This is the correct continuous-listening pattern for Android STT.
            Future.delayed(const Duration(milliseconds: 200), _startWakeSession);
          }
        }
      },
    );
    debugPrint('LIMPO TASK: STT ready=$_sttReady');
  }

  // ── Wake session ─────────────────────────────────────────────────────────────
  //
  // KEY DESIGN: Android STT cannot hold a single session open forever.
  // It always ends after pauseFor (silence) or listenFor (max time).
  // The correct approach is NOT to fight this — instead, let each session
  // end naturally and immediately restart a new one in onStatus('done').
  //
  // pauseFor: 2 s  — ends the session 2 s after the user stops speaking.
  //                  Short enough that the restart is quick and seamless,
  //                  long enough to not cut off mid-sentence.
  // listenFor: 10 s — max session length. Shorter = more frequent restarts
  //                   but more reliable. Android kills longer sessions more.

  void _startWakeSession() {
    // Mutex: if already active or in command mode, do nothing.
    if (_stopped || _isProcessing || _sessionActive) return;
    if (_speech?.isListening ?? false) return;

    _sessionActive = true;
    _latestText    = '';

    _initStt().then((_) {
      if (!_sttReady || _stopped || _isProcessing) {
        _sessionActive = false;
        return;
      }

      debugPrint('LIMPO TASK: WAKE SESSION OPEN');
      _sendState('idle');
      _notify('Say "Hey Limpo"');

      _speech!.listen(
        onResult: (result) {
          if (_stopped || _isProcessing) return;
          final text = result.recognizedWords.toLowerCase().trim();
          if (text.isEmpty) return;
          debugPrint('LIMPO WAKE: "$text"');

          // Wake word matching — covers common mis-transcriptions of "Limpo"
          if (_isWakeWord(text)) {
            debugPrint('LIMPO TASK: *** WAKE WORD DETECTED ***');
            // Set _isProcessing synchronously here so that the onStatus('done')
            // callback (which fires right after stop()) does NOT restart the
            // wake loop — command mode takes over instead.
            _isProcessing  = true;
            _sessionActive = false;
            _speech!.stop();
            _onWakeDetected();
          }
        },
        // Short session — Android is more reliable with short windows.
        // onStatus('done') will immediately open a new session.
        listenFor: const Duration(seconds: 10),
        // 2 s silence = session ends. User saying the wake word resets this.
        pauseFor:  const Duration(seconds: 2),
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      );
    });
  }

  // ── Wake word matching ───────────────────────────────────────────────────────
  //
  // Android STT often mis-transcribes "Limpo" as: lipo, limp, olympo, limbo,
  // tempo, simple, symbol, etc. Cast a wide net.

  bool _isWakeWord(String text) {
    return text.contains('limpo')    ||
        text.contains('hey limp') ||
        text.contains('hey lipo') ||
        text.contains('hey limb') ||
        text.contains('hey lime') ||
        text.contains('olympo')   ||
        text.contains('limbo')    ||
        // Phonetic fallbacks
        text.contains('lempo')    ||
        text.contains('lembo')    ||
        text.contains('a limpo')  ||
        // Full phrase variants
        text == 'limpo'           ||
        RegExp(r'\bh[aei]y\s+li[a-z]{1,4}o\b').hasMatch(text);
  }

  // ── Wake detected → speak "Yes?" → listen for command ───────────────────────

  Future<void> _onWakeDetected() async {
    debugPrint('LIMPO TASK: entering command mode');
    _sendState('wakeWord');
    _notify('Listening…');

    await _speak('Yes?');
    await _listenForCommand();
  }

  // ── Command listening ────────────────────────────────────────────────────────

  Future<void> _listenForCommand() async {
    if (!_sttReady) await _initStt();
    if (!_sttReady) {
      await _speak("Sorry, speech recognition isn't available.");
      _isProcessing = false;
      _startWakeSession();
      return;
    }

    _latestText = '';
    _sendState('listening');
    debugPrint('LIMPO TASK: >>> COMMAND LISTENING <<<');

    _speech!.listen(
      onResult: (result) {
        final text = result.recognizedWords.trim();
        if (text.isNotEmpty) {
          _latestText = text;
          debugPrint('LIMPO CMD: "$text"');
          _sendData('spoken:$text');
        }
      },
      listenFor: const Duration(seconds: 12),
      pauseFor:  const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: false,
      listenMode: ListenMode.dictation,
    );

    // Wait for STT to actually start (up to 1.5 s)
    for (var i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_speech!.isListening) break;
    }
    debugPrint('LIMPO CMD: mic open=${_speech!.isListening}');

    // Wait for session to end
    final deadline = DateTime.now().add(const Duration(seconds: 18));
    while (_speech!.isListening && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    await _processCommand();
  }

  Future<void> _processCommand() async {
    final cmd = _latestText.trim();

    if (cmd.isEmpty) {
      debugPrint('LIMPO TASK: no command heard — back to wake');
      _isProcessing = false;
      _startWakeSession();
      return;
    }

    debugPrint('LIMPO TASK: command="$cmd"');
    _sendState('processing');
    _notify(cmd);

    String reply;
    try {
      reply = await _cmd!.handleCommand(cmd);
    } catch (e) {
      reply = 'Sorry, something went wrong.';
      debugPrint('LIMPO CMD ERROR: $e');
    }

    debugPrint('LIMPO TASK: reply="$reply"');
    _sendData('reply:$reply');
    await _speak(reply);

    _isProcessing = false;
    _sendState('idle');
    _notify('Say "Hey Limpo"');
    await Future.delayed(const Duration(milliseconds: 300));
    _startWakeSession();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _sendState(String s) => _sendData('state:$s');

  void _sendData(String msg) {
    try { FlutterForegroundTask.sendDataToMain(msg); } catch (_) {}
  }

  void _notify(String text) {
    try {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Limpo AI',
        notificationText: text,
      );
    } catch (_) {}
  }
}