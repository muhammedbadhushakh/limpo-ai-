import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class CallService {
  /// Dial a phone number or search contacts by name.
  /// Returns the display name used (number or contact name).
  Future<String> call(String target) async {
    final trimmed = target.trim();

    // If it looks like a phone number, dial directly
    if (RegExp(r'^[+\d\s\-()]{6,}$').hasMatch(trimmed)) {
      return await _dialNumber(trimmed);
    }

    // Otherwise search contacts by name
    return await _callContactByName(trimmed);
  }

  Future<String> _dialNumber(String number) async {
    final clean = number.replaceAll(RegExp(r'[\s\-()]'), '');
    final uri   = Uri(scheme: 'tel', path: clean);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return number;
    }
    throw Exception('Cannot launch dialer');
  }

  Future<String> _callContactByName(String name) async {
    final granted = await Permission.contacts.request();
    if (!granted.isGranted) {
      throw Exception('Contacts permission denied');
    }

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final lowerName = name.toLowerCase();

    Contact? match;
    for (final c in contacts) {
      if (c.displayName.toLowerCase().contains(lowerName)) {
        match = c;
        break;
      }
    }

    if (match == null || match.phones.isEmpty) {
      throw Exception('Contact not found: $name');
    }

    final number = match.phones.first.number;
    await _dialNumber(number);
    return match.displayName;
  }
}