import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  // ⚠️  Replace with your actual Anthropic API key
  static const String _apiKey = 'YOUR_ANTHROPIC_API_KEY_HERE';
  static const String _url    = 'https://api.anthropic.com/v1/messages';

  static const String _system =
      'You are Limpo, a smart Android voice assistant. '
      'Give very short, natural, spoken responses — maximum 2 sentences. '
      'No markdown, no lists. Sound like a helpful friend, not a robot.';

  Future<String> ask(String userQuery) async {
    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-sonnet-4-20250514',
          'max_tokens': 200,
          'system': _system,
          'messages': [
            {'role': 'user', 'content': userQuery},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['content'] as List)
            .firstWhere((b) => b['type'] == 'text', orElse: () => {'text': ''})['text']
            .toString()
            .trim();
      }

      return "Sorry, I couldn't reach my brain right now.";
    } catch (_) {
      return "I'm having trouble connecting. Please check your internet.";
    }
  }
}