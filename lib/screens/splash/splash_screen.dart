// lib/screens/splash/splash_screen.dart

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_service.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';
import '../map/map_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _startAppRouting();
  }

  Future<void> _startAppRouting() async {
    // 1. ADIM: VERSİYON KONTROLÜ
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      final versionData = await _apiService.checkAppVersion(currentVersion);

      if (!mounted) return;

      if (versionData["isUpdateRequired"] == true) {
        _showForceUpdateDialog(versionData["updateUrl"], versionData["latestVersion"]);
        return; // Güncelleme lazımsa burada dur, içeri alma!
      }
    } catch (e) {
      // Sürüm kontrolü başarısız olursa çalışmaya devam et (Fail-Safe)
    }

    // 2. ADIM: TOKEN (BENİ HATIRLA) KONTROLÜ
    bool isLoggedIn = await ref.read(authProvider.notifier).checkAutoLogin();
    
    if (!mounted) return;

    if (isLoggedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MapScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  void _showForceUpdateDialog(String url, String latestVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.system_update_alt, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Text("Zorunlu Güncelleme", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Text("Uygulamanın yeni bir sürümü (v$latestVersion) mevcut. Saha operasyonlarına devam edebilmek için uygulamanızı güncellemeniz gerekmektedir."),
          actions: [
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final Uri updateUri = Uri.parse(url);
                  if (await canLaunchUrl(updateUri)) {
                    await launchUrl(updateUri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.download, color: Colors.white),
                label: const Text("Hemen Güncelle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Görsel açılış ekranımız (Logomuz ortada bekliyor)
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/icon.png', width: 120, height: 120),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.blue),
            const SizedBox(height: 10),
            const Text("Sistem hazırlanıyor...", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}