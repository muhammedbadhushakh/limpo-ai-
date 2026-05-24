// // limpo_assistant_service.dart
// //
// // Runs entirely inside the Flutter app — no foreground service, no isolates.
// // The STT/TTS/command loop lives here. As long as the app is in the foreground
// // (or Android doesn't suspend it) the assistant is active.
// //
// // ARCHITECTURE:
// //   _state stream  →  HomeScreen listens and updates its UI
// //   _spokenText    →  what the user said (shown in the bubble)
// //   _replyText     →  what Limpo replied (shown in the bubble)
//
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter_tts/flutter_tts.dart';
// import 'package:speech_to_text/speech_to_text.dart';
//
// import 'command_service.dart';
// import '../utils/constants.dart';
//
// class LimpoAssistantService {
//   // ── Singleton ───────────────────────────────────────────────────────────────
//   static final LimpoAssistantService _instance =
//   LimpoAssistantService._internal();
//   factory LimpoAssistantService() => _instance;
//   LimpoAssistantService._internal();
//
//   // ── Public streams ──────────────────────────────────────────────────────────
//   final _stateCtrl   = StreamController<AssistantState>.broadcast();
//   final _spokenCtrl  = StreamController<String>.broadcast();
//   final _replyCtrl   = StreamController<String>.broadcast();
//
//   Stream<AssistantState> get stateStream  => _stateCtrl.stream;
//   Stream<String>         get spokenStream => _spokenCtrl.stream;
//   Stream<String>         get replyStream  => _replyCtrl.stream;
//
//   AssistantState get currentState => _state;
//
//   // ── Private ─────────────────────────────────────────────────────────────────
//   final FlutterTts      _tts    = FlutterTts();
//   final SpeechToText    _speech = SpeechToText();
//   final CommandService  _cmd    = CommandService();
//
//   bool _sttReady      = false;
//   bool _isProcessing  = false;   // true while in wake→command→reply cycle
//   bool _sessionActive = false;   // true while _speech.listen() is open
//   bool _running       = false;   // false = service stopped
//   AssistantState _state = AssistantState.idle;
//
//   String _latestText = '';
//
//   // ── Start / Stop ────────────────────────────────────────────────────────────
//
//   Future<void> start() async {
//     if (_running) {
//       debugPrint('LIMPO: already running — restarting wake loop');
//       _isProcessing  = false;
//       _sessionActive = false;
//       await _speech.stop();
//       await Future.delayed(const Duration(milliseconds: 300));
//       _startWakeSession();
//       return;
//     }
//
//     _running = true;
//     debugPrint('LIMPO: starting in-app service');
//
//     await _initTts();
//     await _initStt();
//     _startWakeSession();
//   }
//
//   Future<void> stop() async {
//     _running       = false;
//     _isProcessing  = false;
//     _sessionActive = false;
//     await _speech.stop();
//     await _tts.stop();
//     _setState(AssistantState.idle);
//     debugPrint('LIMPO: stopped');
//   }
//
//   /// Called when the user taps the mic button — skips wake word and goes
//   /// straight into command-listening mode.
//   Future<void> triggerManually() async {
//     if (!_running) await start();
//     if (_isProcessing) return;
//
//     _isProcessing  = true;
//     _sessionActive = false;
//     await _speech.stop();
//     await Future.delayed(const Duration(milliseconds: 250));
//     _onWakeDetected();
//   }
//
//   // ── TTS ─────────────────────────────────────────────────────────────────────
//
//   Future<void> _initTts() async {
//     await _tts.setLanguage('en-US');
//     await _tts.setSpeechRate(0.5);
//     await _tts.setVolume(1.0);
//     await _tts.setPitch(1.0);
//     debugPrint('LIMPO: TTS ready');
//   }
//
//   Future<void> _speak(String text) async {
//     _setState(AssistantState.speaking);
//
//     final completer = Completer<void>();
//     _tts.setCompletionHandler(() { if (!completer.isCompleted) completer.complete(); });
//     _tts.setCancelHandler(()    { if (!completer.isCompleted) completer.complete(); });
//     _tts.setErrorHandler((_)    { if (!completer.isCompleted) completer.complete(); });
//
//     await _tts.stop();
//     await _tts.speak(text);
//
//     await completer.future.timeout(
//       Duration(seconds: (text.length / 8).ceil().clamp(3, 30)),
//       onTimeout: () {},
//     );
//
//     // Short gap so TTS audio doesn't bleed into STT
//     await Future.delayed(const Duration(milliseconds: 600));
//   }
//
//   // ── STT init ─────────────────────────────────────────────────────────────────
//
//   Future<void> _initStt() async {
//     if (_sttReady) return;
//     debugPrint('LIMPO: initializing STT');
//
//     _sttReady = await _speech.initialize(
//       onError: (e) {
//         debugPrint('LIMPO STT ERROR: ${e.errorMsg}');
//         if (e.errorMsg == 'error_client' || e.errorMsg == 'error_permission') {
//           _sttReady = false;
//         }
//         _sessionActive = false;
//         if (!_isProcessing && _running) {
//           Future.delayed(const Duration(milliseconds: 500), _startWakeSession);
//         }
//       },
//       onStatus: (status) {
//         debugPrint('LIMPO STT STATUS: $status');
//         if (status == 'done' || status == 'notListening') {
//           _sessionActive = false;
//           // Self-restart: only in wake mode (not while processing a command)
//           if (!_isProcessing && _running) {
//             Future.delayed(const Duration(milliseconds: 200), _startWakeSession);
//           }
//         }
//       },
//     );
//
//     debugPrint('LIMPO: STT ready=$_sttReady');
//   }
//
//   // ── Wake session ─────────────────────────────────────────────────────────────
//   //
//   // Keeps a short (10 s) STT window open to detect "Hey Limpo".
//   // When it ends (silence / timeout), onStatus('done') immediately opens
//   // a fresh session — seamless continuous listening with no manual timer.
//
//   void _startWakeSession() {
//     if (!_running || _isProcessing || _sessionActive) return;
//     if (_speech.isListening) return;
//
//     _sessionActive = true;
//     _latestText    = '';
//
//     _initStt().then((_) {
//       if (!_sttReady || !_running || _isProcessing) {
//         _sessionActive = false;
//         return;
//       }
//
//       _setState(AssistantState.idle);
//       debugPrint('LIMPO: WAKE SESSION OPEN');
//
//       _speech.listen(
//         onResult: (result) {
//           if (!_running || _isProcessing) return;
//           final text = result.recognizedWords.toLowerCase().trim();
//           if (text.isEmpty) return;
//           debugPrint('LIMPO WAKE: "$text"');
//
//           if (_isWakeWord(text)) {
//             debugPrint('LIMPO: *** WAKE WORD DETECTED ***');
//             _isProcessing  = true;
//             _sessionActive = false;
//             _speech.stop();
//             _onWakeDetected();
//           }
//         },
//         listenFor: const Duration(seconds: 10),
//         pauseFor:  const Duration(seconds: 2),
//         partialResults: true,
//         cancelOnError: false,
//         listenMode: ListenMode.dictation,
//       );
//     });
//   }
//
//   // ── Wake word matching ────────────────────────────────────────────────────────
//
//   bool _isWakeWord(String text) {
//     return text.contains('limpo')    ||
//         text.contains('hey limp') ||
//         text.contains('hey lipo') ||
//         text.contains('hey limb') ||
//         text.contains('hey lime') ||
//         text.contains('olympo')   ||
//         text.contains('limbo')    ||
//         text.contains('lempo')    ||
//         text.contains('lembo')    ||
//         text.contains('a limpo')  ||
//         text == 'limpo'           ||
//         RegExp(r'\bh[aei]y\s+li[a-z]{1,4}o\b').hasMatch(text);
//   }
//
//   // ── Wake detected → "Yes?" → command listen ───────────────────────────────────
//
//   Future<void> _onWakeDetected() async {
//     debugPrint('LIMPO: entering command mode');
//     _setState(AssistantState.wakeWord);
//
//     await _speak('Yes?');
//     await _listenForCommand();
//   }
//
//   // ── Command listening ──────────────────────────────────────────────────────────
//
//   Future<void> _listenForCommand() async {
//     if (!_sttReady) await _initStt();
//     if (!_sttReady) {
//       await _speak("Sorry, speech recognition isn't available.");
//       _isProcessing = false;
//       _startWakeSession();
//       return;
//     }
//
//     _latestText = '';
//     _setState(AssistantState.listening);
//     debugPrint('LIMPO: >>> COMMAND LISTENING <<<');
//
//     _speech.listen(
//       onResult: (result) {
//         final text = result.recognizedWords.trim();
//         if (text.isNotEmpty) {
//           _latestText = text;
//           debugPrint('LIMPO CMD: "$text"');
//           _spokenCtrl.add(text);
//         }
//       },
//       listenFor: const Duration(seconds: 12),
//       pauseFor:  const Duration(seconds: 3),
//       partialResults: true,
//       cancelOnError: false,
//       listenMode: ListenMode.dictation,
//     );
//
//     // Wait for STT to actually start (up to 1.5 s)
//     for (var i = 0; i < 15; i++) {
//       await Future.delayed(const Duration(milliseconds: 100));
//       if (_speech.isListening) break;
//     }
//     debugPrint('LIMPO CMD: mic open=${_speech.isListening}');
//
//     // Wait for session to end
//     final deadline = DateTime.now().add(const Duration(seconds: 18));
//     while (_speech.isListening && DateTime.now().isBefore(deadline)) {
//       await Future.delayed(const Duration(milliseconds: 100));
//     }
//
//     await _processCommand();
//   }
//
//   Future<void> _processCommand() async {
//     final cmd = _latestText.trim();
//
//     if (cmd.isEmpty) {
//       debugPrint('LIMPO: no command heard — back to wake');
//       _isProcessing = false;
//       _startWakeSession();
//       return;
//     }
//
//     debugPrint('LIMPO: command="$cmd"');
//     _setState(AssistantState.processing);
//
//     String reply;
//     try {
//       reply = await _cmd.handleCommand(cmd);
//     } catch (e) {
//       reply = 'Sorry, something went wrong.';
//       debugPrint('LIMPO CMD ERROR: $e');
//     }
//
//     debugPrint('LIMPO: reply="$reply"');
//     _replyCtrl.add(reply);
//
//     await _speak(reply);
//
//     _isProcessing = false;
//     _setState(AssistantState.idle);
//     await Future.delayed(const Duration(milliseconds: 300));
//     _startWakeSession();
//   }
//
//   // ── Helpers ───────────────────────────────────────────────────────────────────
//
//   void _setState(AssistantState s) {
//     _state = s;
//     if (!_stateCtrl.isClosed) _stateCtrl.add(s);
//   }
//
//   void dispose() {
//     _stateCtrl.close();
//     _spokenCtrl.close();
//     _replyCtrl.close();
//   }
// }