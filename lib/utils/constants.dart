import 'package:flutter/material.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────
class AppColors {
  static const Color background   = Color(0xFF080B14);
  static const Color bgGradStart  = Color(0xFF0D1117);
  static const Color bgGradEnd    = Color(0xFF060810);

  static const Color primary      = Color(0xFF00E676);
  static const Color accent1      = Color(0xFF7C4DFF);
  static const Color accent2      = Color(0xFF00B0FF);
  static const Color accent3      = Color(0xFFFF4081);

  static const Color glass        = Color(0x14FFFFFF);
  static const Color glassBorder  = Color(0x28FFFFFF);
  static const Color glassShine   = Color(0x0DFFFFFF);

  static const Color text         = Colors.white;
  static const Color textDim      = Color(0x80FFFFFF);
  static const Color textHint     = Color(0x40FFFFFF);

  static const Color stateIdle       = Color(0xFF00E676);
  static const Color stateListening  = Color(0xFF00B0FF);
  static const Color stateProcessing = Color(0xFFFFD740);
  static const Color stateSpeaking   = Color(0xFF7C4DFF);
  static const Color stateError      = Color(0xFFFF5252);
}

// ─── Strings ──────────────────────────────────────────────────────────────────
class AppStrings {
  static const String appName      = "LIMPO AI";
  static const String welcomeText  = 'Say "Hey Limpo" or tap the orb';
  static const String wakeHint     = 'Say "Hey Limpo" or tap the orb';
  static const String sleeping     = "Sleeping  •  Say Hey Limpo";
  static const String wakeWord     = "Hey! I'm listening...";
  static const String listening    = "Speak your command...";
  static const String thinking     = "Let me think...";
  static const String speaking     = "Speaking...";
}

// ─── Assistant State ──────────────────────────────────────────────────────────
enum AssistantState { idle, wakeWord, listening, processing, speaking }

extension AssistantStateX on AssistantState {
  String get label {
    switch (this) {
      case AssistantState.idle:       return AppStrings.sleeping;
      case AssistantState.wakeWord:   return AppStrings.wakeWord;
      case AssistantState.listening:  return AppStrings.listening;
      case AssistantState.processing: return AppStrings.thinking;
      case AssistantState.speaking:   return AppStrings.speaking;
    }
  }

  Color get color {
    switch (this) {
      case AssistantState.idle:       return AppColors.stateIdle;
      case AssistantState.wakeWord:   return AppColors.stateListening;
      case AssistantState.listening:  return AppColors.stateListening;
      case AssistantState.processing: return AppColors.stateProcessing;
      case AssistantState.speaking:   return AppColors.stateSpeaking;
    }
  }

  IconData get icon {
    switch (this) {
      case AssistantState.idle:       return Icons.nights_stay_rounded;
      case AssistantState.wakeWord:   return Icons.hearing_rounded;
      case AssistantState.listening:  return Icons.mic_rounded;
      case AssistantState.processing: return Icons.psychology_rounded;
      case AssistantState.speaking:   return Icons.volume_up_rounded;
    }
  }
}