// lib/providers/auth_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/network/api_service.dart';
import '../core/utils/app_logger.dart'; // EKSİK OLAN IMPORT EKLENDİ

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final String? errorMessage;

  AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.errorMessage,
  });

  AuthState copyWith({bool? isLoading, bool? isAuthenticated, String? errorMessage}) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  AuthState build() {
    return AuthState(); 
  }

  // SPLASH EKRANININ ÇAĞIRACAĞI "BENİ HATIRLA" METODU
  Future<bool> checkAutoLogin() async {
    final token = await _storage.read(key: 'jwt_token');
    
    if (token != null) {
      AppLogger.info("Beni Hatırla: Geçerli token bulundu, direkt içeri alınıyor.");
      // State'i güncelleyerek uygulamanın yetkili olduğunu bildiriyoruz
      state = state.copyWith(isAuthenticated: true); 
      return true;
    }
    
    return false;
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    bool success = await _apiService.login(username, password);

    if (success) {
      state = state.copyWith(isLoading: false, isAuthenticated: true);
      return true;
    } else {
      state = state.copyWith(
        isLoading: false, 
        isAuthenticated: false,
        errorMessage: "Kullanıcı adı veya şifre hatalı!"
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'jwt_token'); // Çıkış yaparken Token'ı imha et
    state = state.copyWith(isAuthenticated: false);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});