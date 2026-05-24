// home_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/background_service.dart';
import '../services/in_app_assistant.dart';
import '../utils/constants.dart';
import '../widgets/mic_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {

  // ── State ──────────────────────────────────────────────────────────────────
  AssistantState _state      = AssistantState.idle;
  String         _statusText = AppStrings.sleeping;
  String         _spokenText = '';
  bool           _bgRunning  = false;

  // ── In-app assistant ───────────────────────────────────────────────────────
  final _inApp = InAppAssistant();
  bool _inAppBusy = false;

  StreamSubscription<dynamic>?       _dataSub;
  StreamSubscription<AssistantState>? _inAppStateSub;
  StreamSubscription<String>?         _inAppTextSub;
  StreamSubscription<String>?         _inAppReplySub;

  // ── Animation controllers ──────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _waveCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double>   _pulseAnim;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _waveCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    );

    _fadeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400), value: 1,
    );

    _checkServiceState();
    _attachToPort();
    _attachInAppStreams();
    _inApp.init(); // pre-warm STT + TTS so first tap is instant
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _inAppStateSub?.cancel();
    _inAppTextSub?.cancel();
    _inAppReplySub?.cancel();
    _inApp.dispose();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Background service port
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkServiceState() async {
    final running = await LimpoBackgroundService.isRunning;
    if (mounted) setState(() => _bgRunning = running);
  }

  void _attachToPort() {
    _dataSub?.cancel();
    _dataSub = null;

    final port = FlutterForegroundTask.receivePort;
    if (port == null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _attachToPort();
      });
      return;
    }

    _dataSub = port.listen((data) {
      if (data is! String) return;

      if (data.startsWith('state:')) {
        _applyStateFromString(data.substring(6));
      } else if (data.startsWith('spoken:')) {
        if (mounted) setState(() => _spokenText = data.substring(7));
      } else if (data.startsWith('reply:')) {
        final msg = data.substring(6);
        if (mounted) setState(() => _spokenText = msg);
        Future.delayed(
          Duration(milliseconds: (msg.length * 60).clamp(2000, 10000)),
              () { if (mounted) setState(() => _spokenText = ''); },
        );
      } else if (data == 'service_started') {
        if (mounted) setState(() => _bgRunning = true);
      }
    });
  }

  Future<void> _applyStateFromString(String s) async {
    final AssistantState next;
    switch (s) {
      case 'wakeWord':   next = AssistantState.wakeWord;   break;
      case 'listening':  next = AssistantState.listening;  break;
      case 'processing': next = AssistantState.processing; break;
      case 'speaking':   next = AssistantState.speaking;   break;
      default:           next = AssistantState.idle;
    }
    await _setStateAnimated(next);
  }

  Future<void> _setStateAnimated(AssistantState s) async {
    await _fadeCtrl.reverse();
    if (mounted) setState(() { _state = s; _statusText = s.label; });
    await _fadeCtrl.forward();

    if (s == AssistantState.listening ||
        s == AssistantState.wakeWord  ||
        s == AssistantState.speaking) {
      _waveCtrl.repeat();
    } else {
      _waveCtrl.stop();
      _waveCtrl.reset();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // In-app assistant streams
  // ─────────────────────────────────────────────────────────────────────────

  void _attachInAppStreams() {
    _inAppStateSub = _inApp.onStateChanged.listen((s) {
      if (mounted) _setStateAnimated(s);
      if (mounted) setState(() => _inAppBusy = _inApp.isBusy);
    });

    _inAppTextSub = _inApp.onTextChanged.listen((t) {
      if (mounted) setState(() => _spokenText = t);
    });

    _inAppReplySub = _inApp.onReply.listen((reply) {
      if (mounted) setState(() => _spokenText = reply);
      Future.delayed(
        Duration(milliseconds: (reply.length * 60).clamp(2000, 10000)),
            () { if (mounted) setState(() => _spokenText = ''); },
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Button handlers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _toggleBackground() async {
    if (_bgRunning) {
      await LimpoBackgroundService.stop();
      await _setStateAnimated(AssistantState.idle);
      if (mounted) setState(() { _bgRunning = false; _spokenText = ''; });
    } else {
      await LimpoBackgroundService.start();
      if (mounted) setState(() => _bgRunning = true);
      _attachToPort();
    }
  }

  Future<void> _onMicTapped() async {
    if (!_bgRunning) {
      await LimpoBackgroundService.start();
      if (mounted) setState(() => _bgRunning = true);
      _attachToPort();
      await Future.delayed(const Duration(milliseconds: 1200));
    }
    await LimpoBackgroundService.triggerManually();
  }

  /// Tap & Talk — runs entirely inside the app, no background cycling.
  Future<void> _onInAppTap() async {
    if (_inAppBusy) return;
    // Pause background service so the two don't fight for the mic
    if (_bgRunning) {
      FlutterForegroundTask.sendDataToTask('stop');
    }
    if (mounted) setState(() => _spokenText = '');
    await _inApp.trigger();
    // Resume background service if it was running before
    if (_bgRunning) {
      await Future.delayed(const Duration(milliseconds: 400));
      FlutterForegroundTask.sendDataToTask('restart');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          _buildBlobBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(),
                _buildSiriOrb(),
                const SizedBox(height: 32),
                _buildStatusText(),
                const SizedBox(height: 16),
                _buildSpokenText(),
                const Spacer(),
                _buildInAppButton(),
                const SizedBox(height: 12),
                MicButton(state: _state, onTap: _onMicTapped),
                const SizedBox(height: 16),
                _buildToggleButton(),
                const SizedBox(height: 16),
                _buildBottomHint(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Widget builders
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBlobBackground() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) => CustomPaint(
        size: MediaQuery.of(context).size,
        painter: _BlobPainter(t: _pulseCtrl.value, state: _state),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            AppStrings.appName,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _bgRunning
                        ? AppColors.stateListening
                        : AppColors.stateIdle,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _bgRunning ? 'LIVE' : 'OFF',
                  style: TextStyle(
                    color: _bgRunning
                        ? AppColors.stateListening
                        : AppColors.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSiriOrb() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _waveCtrl]),
      builder: (_, __) {
        final isActive = _state != AssistantState.idle;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (isActive) ...[
              _GlowRing(radius: 200, color: _state.color.withOpacity(0.05)),
              _GlowRing(radius: 160, color: _state.color.withOpacity(0.08)),
            ],
            Transform.scale(
              scale: isActive ? _pulseAnim.value : 1.0,
              child: GestureDetector(
                onTap: _toggleBackground,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isActive
                        ? RadialGradient(colors: [
                      _state.color.withOpacity(0.9),
                      _state.color.withOpacity(0.3),
                      Colors.transparent,
                    ], stops: const [0.0, 0.5, 1.0])
                        : RadialGradient(colors: [
                      AppColors.stateIdle.withOpacity(0.4),
                      AppColors.stateIdle.withOpacity(0.05),
                      Colors.transparent,
                    ], stops: const [0.0, 0.5, 1.0]),
                    boxShadow: [
                      BoxShadow(
                        color: _state.color.withOpacity(isActive ? 0.5 : 0.2),
                        blurRadius: isActive ? 60 : 30,
                        spreadRadius: isActive ? 10 : 2,
                      ),
                    ],
                  ),
                  child: _buildOrbContent(isActive),
                ),
              ),
            ),
            if (_state == AssistantState.listening ||
                _state == AssistantState.speaking)
              _WaveBars(animation: _waveCtrl, color: _state.color),
          ],
        );
      },
    );
  }

  Widget _buildOrbContent(bool isActive) {
    if (_state == AssistantState.processing) {
      return Center(
        child: SizedBox(
          width: 36, height: 36,
          child: CircularProgressIndicator(
            color: _state.color, strokeWidth: 2.5,
          ),
        ),
      );
    }
    return Center(
      child: Icon(
        _state.icon,
        color: isActive ? Colors.white : _state.color,
        size: 48,
      ),
    );
  }

  Widget _buildStatusText() {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: Text(
        _statusText,
        style: TextStyle(
          color: _state.color,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSpokenText() {
    if (_spokenText.isEmpty) return const SizedBox(height: 48);
    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Text(
          _spokenText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.text, fontSize: 16, height: 1.5,
          ),
        ),
      ),
    );
  }

  /// Tap & Talk button — opens the mic once inside the app, no background loop.
  Widget _buildInAppButton() {
    final busy  = _inAppBusy;
    final color = busy ? AppColors.stateListening : AppColors.accent2;
    return GestureDetector(
      onTap: _onInAppTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(busy ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: color, width: 1.6),
          boxShadow: busy
              ? [BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 20,
            spreadRadius: 2,
          )]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            busy
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: color, strokeWidth: 2,
              ),
            )
                : Icon(Icons.record_voice_over_rounded, color: color, size: 20),
            const SizedBox(width: 10),
            Text(
              busy ? 'Listening…' : 'Tap & Talk  (in-app)',
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton() {
    return GestureDetector(
      onTap: _toggleBackground,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          color: _bgRunning
              ? AppColors.stateError.withOpacity(0.15)
              : AppColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: _bgRunning ? AppColors.stateError : AppColors.primary,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _bgRunning
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
              color: _bgRunning ? AppColors.stateError : AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              _bgRunning
                  ? 'Stop Background Listening'
                  : 'Start Background Listening',
              style: TextStyle(
                color: _bgRunning ? AppColors.stateError : AppColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomHint() {
    if (_inAppBusy) {
      return const Text(
        'Speak your command — mic is open',
        style: TextStyle(
          color: AppColors.textHint, fontSize: 13, letterSpacing: 0.5,
        ),
      );
    }
    return Text(
      _bgRunning
          ? 'Background: say "Hey Limpo"  •  or tap Tap & Talk'
          : 'Tap & Talk for instant mic  •  or start background mode',
      style: const TextStyle(
        color: AppColors.textHint, fontSize: 13, letterSpacing: 0.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wave bars
// ─────────────────────────────────────────────────────────────────────────────

class _WaveBars extends StatelessWidget {
  final Animation<double> animation;
  final Color color;
  const _WaveBars({required this.animation, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t = animation.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(7, (i) {
            final h = 12.0 +
                28.0 * (0.5 + 0.5 * sin(t * 2 * pi + i * 0.7 + (i % 3) * 1.1)).abs();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 4,
              height: h,
              decoration: BoxDecoration(
                color: color.withOpacity(0.85),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glow ring
// ─────────────────────────────────────────────────────────────────────────────

class _GlowRing extends StatelessWidget {
  final double radius;
  final Color color;
  const _GlowRing({required this.radius, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius,
      height: radius,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background blob painter
// ─────────────────────────────────────────────────────────────────────────────

class _BlobPainter extends CustomPainter {
  final double t;
  final AssistantState state;
  _BlobPainter({required this.t, required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    void blob(double cx, double cy, double r, Color c) {
      canvas.drawCircle(
        Offset(cx * size.width, cy * size.height),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [c.withOpacity(0.25), Colors.transparent],
          ).createShader(Rect.fromCircle(
            center: Offset(cx * size.width, cy * size.height),
            radius: r,
          )),
      );
    }
    final pulse = 0.9 + 0.1 * sin(t * pi);
    blob(0.15, 0.20, 200 * pulse, AppColors.accent1);
    blob(0.85, 0.25, 180 * pulse, AppColors.accent2);
    blob(0.50, 0.85, 220 * pulse, state.color);
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.t != t || old.state != state;
}