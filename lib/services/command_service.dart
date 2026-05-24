import 'app_launcher_service.dart';
import 'ai_service.dart';
import 'call_service.dart';
import 'sms_service.dart';

class CommandService {
  final AppLauncherService _launcher    = AppLauncherService();
  final AIService          _ai          = AIService();
  final CallService        _callService = CallService();
  final SMSService         _smsService  = SMSService();

  /// Returns the assistant's spoken reply.
  /// NOTE: TTS is the caller's responsibility — do NOT speak inside here.
  Future<String> handleCommand(String command) async {
    final cmd = command.toLowerCase().trim();

    // ── OPEN APP ──────────────────────────────────────────────────────────────
    final openMatch = RegExp(r'open\s+(.+)').firstMatch(cmd);
    if (openMatch != null) {
      final appName = openMatch.group(1)!.trim();
      final opened = await _launcher.openAppByName(appName);
      return opened
          ? "Opening $appName"
          : "Sorry, I couldn't find $appName on your phone.";
    }

    // ── CALL ──────────────────────────────────────────────────────────────────
    final callMatch = RegExp(r'call\s+(.+)').firstMatch(cmd);
    if (callMatch != null) {
      final target = callMatch.group(1)!.trim();
      try {
        final name = await _callService.call(target);
        return "Calling $name";
      } catch (e) {
        return "Sorry, I couldn't call $target.";
      }
    }

    // ── WHATSAPP ──────────────────────────────────────────────────────────────
    // Matches patterns like:
    //   "whatsapp John hello"
    //   "send whatsapp to John"
    //   "send whatsapp message to John hey there"
    //   "whatsapp message to John"
    final waMatch = RegExp(
      r'(?:send\s+)?whatsapp(?:\s+(?:message|msg))?\s+(?:to\s+)?(\w+)(?:\s+(.+))?',
    ).firstMatch(cmd);
    if (waMatch != null) {
      final target = waMatch.group(1)!.trim();
      final body   = waMatch.group(2)?.trim();
      try {
        final name = await _smsService.sendWhatsApp(target, body: body);
        return body != null
            ? "Opening WhatsApp to send message to $name"
            : "Opening WhatsApp chat with $name";
      } catch (e) {
        return "Sorry, I couldn't open WhatsApp for $target.";
      }
    }

    // ── SMS ───────────────────────────────────────────────────────────────────
    // Matches:
    //   "send message to John"
    //   "send sms to John hello"
    //   "text John hello"
    //   "send text to John"
    final smsMatch = RegExp(
      r'(?:send\s+(?:message|sms|text)\s+to|text)\s+(\w+)(?:\s+(.+))?',
    ).firstMatch(cmd);
    if (smsMatch != null) {
      final target = smsMatch.group(1)!.trim();
      final body   = smsMatch.group(2)?.trim();
      try {
        final name = await _smsService.send(target, body: body);
        return "Opening SMS to $name";
      } catch (e) {
        return "Couldn't send a message to $target.";
      }
    }

    // ── SETTINGS ──────────────────────────────────────────────────────────────
    if (cmd.contains('open settings') || cmd == 'settings') {
      await _launcher.openSettings();
      return "Opening Settings";
    }

    // ── CAMERA ────────────────────────────────────────────────────────────────
    if (cmd.contains('open camera') || cmd == 'camera') {
      await _launcher.openCamera();
      return "Opening Camera";
    }

    // ── AI FALLBACK ───────────────────────────────────────────────────────────
    return await _ai.ask(command);
  }
}