import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class SMSService {
  // ─── Public entry points ──────────────────────────────────────────────────

  /// Opens the default SMS app pre-filled with [target] and optional [body].
  Future<String> send(String target, {String? body}) async {
    final number = await _resolveNumber(target);
    return await _openSMS(number, body: body);
  }

  /// Opens WhatsApp chat with [target] and optional [body].
  Future<String> sendWhatsApp(String target, {String? body}) async {
    final number = await _resolveNumber(target);
    return await _openWhatsApp(number, body: body);
  }

  // ─── Number resolution ────────────────────────────────────────────────────

  /// Returns a phone number string — either the raw number if [target] already
  /// looks like one, or the first number found in contacts matching the name.
  Future<String> _resolveNumber(String target) async {
    final trimmed = target.trim();
    if (RegExp(r'^[+\d\s\-()]{6,}$').hasMatch(trimmed)) {
      // Already a number — clean and return directly
      return trimmed.replaceAll(RegExp(r'[\s\-()]'), '');
    }
    return await _numberFromContactName(trimmed);
  }

  Future<String> _numberFromContactName(String name) async {
    final granted = await Permission.contacts.request();
    if (!granted.isGranted) throw Exception('Contacts permission denied');

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final lowerName = name.toLowerCase();

    for (final c in contacts) {
      if (c.displayName.toLowerCase().contains(lowerName)) {
        if (c.phones.isEmpty) throw Exception('Contact "$name" has no phone number');
        // Strip all formatting — WhatsApp needs a clean international number
        return c.phones.first.number.replaceAll(RegExp(r'[\s\-()]'), '');
      }
    }
    throw Exception('Contact not found: $name');
  }

  // ─── SMS ──────────────────────────────────────────────────────────────────

  Future<String> _openSMS(String number, {String? body}) async {
    final uri = Uri(
      scheme: 'sms',
      path: number,
      queryParameters: (body != null && body.isNotEmpty) ? {'body': body} : null,
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return number;
    }
    throw Exception('Cannot open SMS app');
  }

  // ─── WhatsApp ─────────────────────────────────────────────────────────────
  //
  // WhatsApp supports two deep-link schemes:
  //   1. wa.me/<number>?text=<message>   — universal link, works on all devices
  //   2. whatsapp://send?phone=<number>&text=<message>  — direct app scheme
  //
  // We try (2) first (opens WhatsApp directly without browser redirect),
  // then fall back to (1) if WhatsApp isn't installed.

  Future<String> _openWhatsApp(String number, {String? body}) async {
    // Ensure number starts with + for international format.
    // If the user's contact has a local number (e.g. 09876543210) WhatsApp
    // still needs the country code. We pass what we have — if it fails,
    // the fallback wa.me link will open a browser page that handles it.
    final encoded = Uri.encodeComponent(body ?? '');

    // Scheme 1: direct WhatsApp intent
    final directUri = Uri.parse(
      'whatsapp://send?phone=$number&text=$encoded',
    );
    if (await canLaunchUrl(directUri)) {
      await launchUrl(directUri, mode: LaunchMode.externalApplication);
      return number;
    }

    // Scheme 2: wa.me universal link fallback
    final webUri = Uri.parse(
      'https://wa.me/$number${body != null && body.isNotEmpty ? "?text=$encoded" : ""}',
    );
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return number;
    }

    throw Exception('WhatsApp is not installed or cannot be opened');
  }
}