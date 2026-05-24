// mic_button.dart
//
// FIX: This file was accidentally overwritten with a duplicate of main.dart
// (contained a full LimpoApp + main() instead of a widget).
// Replaced with the actual MicButton widget used by HomeScreen.

import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../services/background_service.dart';

/// A tappable mic orb button that triggers the assistant manually
/// (i.e. skips the wake word and goes straight to command listening).
///
/// Used as an alternative to saying "Hey Limpo" — tapping this button
/// calls [_onWakeWordDetected] directly via [LimpoBackgroundService.triggerManually].
class MicButton extends StatelessWidget {
  final AssistantState state;
  final VoidCallback onTap;

  const MicButton({
    super.key,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = state != AssistantState.idle;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? state.color.withOpacity(0.15)
              : AppColors.glass,
          border: Border.all(
            color: isActive ? state.color : AppColors.glassBorder,
            width: 1.5,
          ),
          boxShadow: isActive
              ? [
            BoxShadow(
              color: state.color.withOpacity(0.35),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ]
              : [],
        ),
        child: Icon(
          state == AssistantState.listening
              ? Icons.mic_rounded
              : Icons.mic_none_rounded,
          color: isActive ? state.color : AppColors.textDim,
          size: 30,
        ),
      ),
    );
  }
}