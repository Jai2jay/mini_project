import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final envFile = File('.env');
  final lines = await envFile.readAsLines();
  String? apiKey;
  for (final line in lines) {
    if (line.startsWith('GEMINI_API_KEY=')) {
      apiKey = line.split('=')[1].trim();
      break;
    }
  }

  if (apiKey == null) {
    print('API key not found');
    return;
  }

  final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
  
  final client = HttpClient();
  final request = await client.getUrl(url);
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  
  print('Status: ${response.statusCode}');
  print('Body: $responseBody');
  
  client.close();
}
