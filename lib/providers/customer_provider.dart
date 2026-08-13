// lib/providers/customer_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/local_db/database_helper.dart';
import '../core/network/api_service.dart';
import '../models/customer_model.dart';
import '../core/utils/app_logger.dart';

class CustomerState {
  final List<CustomerModel> customers;
  final bool isLoading;
  final String? errorMessage;
  final bool isOffline; 

  CustomerState({
    this.customers = const [],
    this.isLoading = false,
    this.errorMessage,
    this.isOffline = false, 
  });

  CustomerState copyWith({List<CustomerModel>? customers, bool? isLoading, String? errorMessage, bool? isOffline}) {
    return CustomerState(
      customers: customers ?? this.customers,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}

class CustomerNotifier extends Notifier<CustomerState> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ApiService _apiService = ApiService();

  @override
  CustomerState build() {
    checkInternetAndSync(); 
    return CustomerState();
  }

  // 1. ARAMA İŞLEMİ (Offline-First: Önce Cihaz, Sonra Bulut)
  Future<void> searchCustomers(String customerId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // 1. ADIM: Cihazın yerel SQLite veritabanına bak
      final localCustomers = await _dbHelper.getCustomersById(customerId);

      if (localCustomers.isNotEmpty) {
        state = state.copyWith(isLoading: false, customers: localCustomers);
        return; 
      }

      // 2. ADIM: Cihazda yoksa Holding'in API sunucusuna git
      final apiCustomers = await _apiService.getCustomerLocations(customerId);
      
      if (apiCustomers.isNotEmpty) {
        state = state.copyWith(isLoading: false, customers: apiCustomers);
      } else {
        state = state.copyWith(isLoading: false, errorMessage: "Müşteri sistemde bulunamadı.", customers: []);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: "Arama sırasında bir hata oluştu.", customers: []);
    }
  }

  // 2. KİRLİ VERİYİ VEYA YENİ MÜŞTERİYİ KAYDETME (Kurumsal Mimari)
  Future<bool> updateAndSyncLocation(String customerId, double lat, double lng, String address) async {
    state = state.copyWith(isLoading: true);

    // KURAL 1: İNTERNET OLSUN VEYA OLMASIN, ÖNCE CİHAZA (SQLITE) KAYDET/GÜNCELLE
    // Bu sayede veri asla kaybolmaz ve "Müşteri bulunamadı" hatası yaşanmaz.
    int localResult = await _dbHelper.updateCustomerLocationLocally(customerId, lat, lng);

    if (localResult > 0) {
      // KURAL 2: Şimdi interneti kontrol et ve buluta göndermeyi dene
      var connectivityResult = await (Connectivity().checkConnectivity());
      bool hasInternet = connectivityResult.contains(ConnectivityResult.mobile) || connectivityResult.contains(ConnectivityResult.wifi);

      if (hasInternet) {
        bool apiSuccess = await _apiService.updateCustomerLocation(customerId, lat, lng, address);
        
        if (!apiSuccess) {
          // İnternet var ama API cevap vermedi (Örn: 500 Server Error) -> Veriyi güvene al (Kuyruğa at)
          AppLogger.error("Sunucu yanıt vermedi! İşlem çevrimdışı kuyruğa alınıyor...");
          await _dbHelper.insertToSyncQueue(customerId, lat, lng, address);
        }
      } else {
        // İnternet hiç yok -> Doğrudan kuyruğa at
        AppLogger.error("İNTERNET YOK! İşlem çevrimdışı kuyruğa alınıyor...");
        state = state.copyWith(isOffline: true);
        await _dbHelper.insertToSyncQueue(customerId, lat, lng, address); 
      }

      // Haritada yeşil pinin anında görünmesi için arayüzü tetikliyoruz
      await searchCustomers(customerId); 
      return true; // Kullanıcı açısından işlem başarılı.
      
    } else {
      state = state.copyWith(isLoading: false, errorMessage: "Cihaz hafızasına kaydedilemedi.");
      return false;
    }
  }

  // 3. İNTERNET GELDİĞİNDE KUYRUĞU ERİTME İŞLEMİ (Background Sync)
  Future<void> checkInternetAndSync() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    bool hasInternet = connectivityResult.contains(ConnectivityResult.mobile) || connectivityResult.contains(ConnectivityResult.wifi);

    if (hasInternet) {
      state = state.copyWith(isOffline: false);
      
      final pendingTasks = await _dbHelper.getPendingSyncs();
      
      if (pendingTasks.isNotEmpty) {
        AppLogger.info("İnternet geldi! Kuyruktaki ${pendingTasks.length} işlem API'ye aktarılıyor...");
        
        for (var task in pendingTasks) {
          bool apiSuccess = await _apiService.updateCustomerLocation(
            task['customerCode'], 
            task['latitude'], 
            task['longitude'], 
            task['address']
          );
          
          if (apiSuccess) {
            await _dbHelper.removeFromSyncQueue(task['id']);
          }
        }
        AppLogger.info("Kuyruk başarıyla eritildi ve sunucu ile senkronize olundu!");
      }
    } else {
      state = state.copyWith(isOffline: true);
    }
  }

  void clearSearch() {
    state = CustomerState();
  }
}

final customerProvider = NotifierProvider<CustomerNotifier, CustomerState>(() {
  return CustomerNotifier();
});