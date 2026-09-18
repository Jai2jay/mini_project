import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'home_screen.dart';

/// Global list of available cameras on the device.
/// Populated once at startup before the app runs.
late List<CameraDescription> cameras;

Future<void> main() async {
  // Ensure Flutter bindings are ready before calling platform channels.
  WidgetsFlutterBinding.ensureInitialized();

  // Global uncaught error handler
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Uncaught Flutter Error: ${details.exception}');
  };

  // Global widget error builder
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return AppErrorScreen(
      errorMessage: details.exceptionAsString(),
    );
  };

  // Load environment variables (API keys) from the .env file.
  await dotenv.load(fileName: ".env");

  // Fetch all available cameras (front, rear, external).
  try {
    cameras = await availableCameras();
  } catch (e) {
    cameras = [];
    debugPrint('Camera discovery notice: $e');
  }

  runApp(const ContactScannerApp());
}

/// Root widget for the ContactScanner application.
class ContactScannerApp extends StatelessWidget {
  const ContactScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ContactScanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF2B3A5E),
        scaffoldBackgroundColor: const Color(0xFF0E1118),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0E1118),
          foregroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.white),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF141720),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF232838), width: 1.0),
          ),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2B3A5E),
          surface: Color(0xFF141720),
          error: Colors.redAccent,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

/// A global error screen displayed when the app encounters an uncaught error.
class AppErrorScreen extends StatelessWidget {
  final String errorMessage;

  const AppErrorScreen({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF6B4EFF),
      ),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 80,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Something went wrong',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  errorMessage,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    // Force restart app by rebuilding root widget
                    runApp(const ContactScannerApp());
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restart'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B4EFF),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(200, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
