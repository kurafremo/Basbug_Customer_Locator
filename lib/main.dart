import 'package:basbug_customer_locator/screens/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'core/utils/app_logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env"); // Ortam değişkenlerini belleğe al

  // YALNIZCA FLUTTER VE ASENKRON HATALARINI YEREL KONSOLA LOGLA
  FlutterError.onError = (errorDetails) {
    AppLogger.error("Flutter Hatası Yakalandı!", errorDetails.exception, errorDetails.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error("Asenkron Hata Yakalandı!", error, stack);
    return true;
  };

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Saha Operasyon Sistemi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue.shade900),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}