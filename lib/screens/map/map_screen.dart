// lib/screens/map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart'; 
import '../../providers/customer_provider.dart';
import '../../models/customer_model.dart';
import '../../core/network/api_service.dart';
import '../auth/login_screen.dart';
import 'dart:async';
import '../customers/unlocated_customers_screen.dart';
import '../customers/located_customers_screen.dart';
import '../../core/network/cached_tile_provider.dart';

bool _isMapCenteredOnUser = false; 

class RemotePinningNotifier extends Notifier<bool> {
  @override
  bool build() => false; 

  void toggleStatus(bool value) {
    state = value;
  }
}

final remotePinningProvider = NotifierProvider<RemotePinningNotifier, bool>(() {
  return RemotePinningNotifier();
});

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = ApiService();
  
  StreamSubscription<Position>? _locationSubscription;
  
  LatLng? _userLocation; 
  final double _allowedRadius = 100.0; 
  final Set<String> _verifiedPins = {};
  
  CustomerModel? _selectedAndVerifiedCustomer;
  String? _resolvedFullAddress;

  bool _isAdmin = false;
  String _userName = "Yükleniyor...";
  String _userRole = "";

  @override
  void initState() {
    super.initState();
    _initLocationService();
    _checkAdminStatus(); 
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customerProvider.notifier).fetchMyCustomers();
    });
  }

  Future<void> _checkAdminStatus() async {
    const storage = FlutterSecureStorage();
    String? role = await storage.read(key: 'saldept_code');
    String? savedUsername = await storage.read(key: 'username');
    if (mounted) {
      setState(() {
        _isAdmin = (role == 'ADMIN' || role == '*');
        _userName = savedUsername ?? "Aktif Personel";
        _userRole = role ?? "Saha Ekibi";
      });
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initLocationService() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Lütfen cihazınızın konum (GPS) servisini açın.', Colors.red);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('Konum izni reddedildi.', Colors.red);
        return;
      }
    }

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
    ).listen((Position position) {
      if (!mounted) return; 

      // SENİOR DOKUNUŞU: Sahte Konum (Fake GPS) Engellemesi
      if (position.isMocked) {
        _showSnackBar('🚨 DİKKAT: Sahte Konum tespit edildi! İşlemler durduruldu.', Colors.red);
        return; 
      }

      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        if (!_isMapCenteredOnUser) {
          _mapController.move(_userLocation!, 16.0); 
          _isMapCenteredOnUser = true; 
        }
      });
    });
  }

  void _performSearch() async {
    FocusScope.of(context).unfocus(); 
    final id = _searchController.text.trim();
    
    if (id.isNotEmpty && !id.contains("Lat:")) {
      final foundCustomer = await ref.read(customerProvider.notifier).searchCustomers(id);
      
      if (foundCustomer != null && mounted) {
        if (foundCustomer.latitude == 0.0 && foundCustomer.longitude == 0.0) {
          if (_userLocation != null) _mapController.move(_userLocation!, 16.0);
        } else {
          _mapController.move(LatLng(foundCustomer.latitude, foundCustomer.longitude), 16.0);
        }
      }
    }
  }

  Future<void> _verifyAndPinLocation(CustomerModel customer) async {
    FocusScope.of(context).unfocus();
    if (_userLocation == null) {
      _showSnackBar('Canlı konumunuz aranıyor, lütfen bekleyin...', Colors.orange);
      return;
    }

    double distanceInMeters = Geolocator.distanceBetween(
      _userLocation!.latitude, _userLocation!.longitude,
      customer.latitude, customer.longitude,
    );

    bool isRemoteAllowed = ref.read(remotePinningProvider);

    if (distanceInMeters <= _allowedRadius) {
      _showSnackBar('Mesafe onaylandı! Adres çözümleniyor...', Colors.blueAccent);
      
      setState(() {
        _verifiedPins.add(customer.customerId + customer.latitude.toString()); 
      });

      String address = await _apiService.getFullAddressFromCoordinates(_userLocation!.latitude, _userLocation!.longitude);
      if (!mounted) return;
      
      String fullDetail = "$address (Lat: ${_userLocation!.latitude.toStringAsFixed(5)}, Lng: ${_userLocation!.longitude.toStringAsFixed(5)})";
      
      setState(() {
        _searchController.text = fullDetail; 
        _selectedAndVerifiedCustomer = customer;
        _resolvedFullAddress = address;
      });

    } else {
      if (isRemoteAllowed) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Mesafe Uyarısı (Yönetici Modu)"),
            content: Text("Sistemdeki konuma ${distanceInMeters.toStringAsFixed(0)} metre uzaktasınız.\n\nYönetici yetkiniz olduğu için uzaktan güncelleyebilirsiniz."),
            actions: [
              TextButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.pop(context);
                },
                child: const Text("İptal", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.pop(context); 
                  _forcePinCurrentLocation(customer); 
                },
                child: const Text("Uzaktan Güncelle", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      } else {
        _showSnackBar('Konuma ${distanceInMeters.toStringAsFixed(0)} metre uzaktasınız. Yaklaşmadan güncelleyemezsiniz!', Colors.red);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _forcePinCurrentLocation(CustomerModel customer) async {
    if (_userLocation == null) {
      _showSnackBar('Canlı konumunuz aranıyor, lütfen bekleyin...', Colors.orange);
      return;
    }

    _showSnackBar('Konum eşitleniyor...', Colors.orange);

    setState(() {
      _verifiedPins.add(customer.customerId + customer.latitude.toString());
    });

    String address = await _apiService.getFullAddressFromCoordinates(_userLocation!.latitude, _userLocation!.longitude);
    if (!mounted) return;

    setState(() {
      _searchController.text = "$address (Özel Konum Ataması)";
      _selectedAndVerifiedCustomer = customer; 
      _resolvedFullAddress = address;
    });
  }

  void _showPendingSyncs() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.4,
          child: Column(
            children: [
              const Icon(Icons.sync_problem, color: Colors.orange, size: 40),
              const SizedBox(height: 10),
              const Text("Bekleyen İşlemler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              const Expanded(
                child: Center(
                  child: Text("Şu an çevrimdışı kuyrukta bekleyen işlem yok.\nİnternet bağlantınız koptuğunda yapılan onaylamalar burada listelenecektir.", textAlign: TextAlign.center),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.pop(context);
                },
                child: const Text("Kapat"),
              )
            ],
          ),
        );
      },
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.blueGrey),
            SizedBox(width: 10),
            Text("Sistem Ayarları"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Uygulama Sürümü: v1.0.1", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Bağlantı Durumu: Çevrimiçi", style: TextStyle(color: Colors.green)),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              title: const Text("Yerel Önbelleği Temizle"),
              onTap: () {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
                _showSnackBar("Önbellek temizlendi.", Colors.green);
              },
            ),
            if (_isAdmin)
              Consumer(
                builder: (context, ref, child) {
                  final isRemoteEnabled = ref.watch(remotePinningProvider);
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: Colors.redAccent, 
                    activeTrackColor: Colors.redAccent.withValues(alpha: 0.5),
                    title: const Text("Uzaktan Güncelleme", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text("Yönetici Yetkisi", style: TextStyle(fontSize: 11)),
                    value: isRemoteEnabled,
                    onChanged: (val) {
                      ref.read(remotePinningProvider.notifier).toggleStatus(val);
                    },
                  );
                },
              )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
            child: const Text("Kapat"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ----------------------------------------------------------------------
    // 🚀 SENİOR DOKUNUŞU: RIVERPOD .select() OPTİMİZASYONU
    // Eskiden tüm sayfayı dinliyorduk (ref.watch(customerProvider)).
    // Artık sayfayı 3 parçaya böldük. Harita sadece liste değişirse çizilecek!
    // ----------------------------------------------------------------------
    final customerList = ref.watch(customerProvider.select((state) => state.customers));
    final isLoading = ref.watch(customerProvider.select((state) => state.isLoading));
    final errorMessage = ref.watch(customerProvider.select((state) => state.errorMessage));

    bool isUnlocated = _selectedAndVerifiedCustomer != null && 
                       _selectedAndVerifiedCustomer!.latitude == 0.0 && 
                       _selectedAndVerifiedCustomer!.longitude == 0.0;

    return Scaffold(
      extendBodyBehindAppBar: true, 
      resizeToAvoidBottomInset: false, 
      onDrawerChanged: (isOpened) {
        if (isOpened) {
          FocusScope.of(context).unfocus();
        }
      },
      appBar: AppBar(
        title: const Text('Müşteri Konum Denetimi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white.withValues(alpha: 0.9), 
        elevation: 0,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
           UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: Colors.blue.shade900),
              accountName: Text("Kullanıcı: ${_userName.toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              accountEmail: Text("Yetki Kodu: $_userRole"),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Colors.blueAccent),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('Harita'),
              onTap: () {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync_problem, color: Colors.orange),
              title: const Text('Bekleyen Senkronizasyonlar'),
              trailing: const CircleAvatar(radius: 12, backgroundColor: Colors.orange, child: Text('0', style: TextStyle(fontSize: 12, color: Colors.white))),
              onTap: () {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
                _showPendingSyncs();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.location_off, color: Colors.redAccent),
              title: const Text('Konumu Olmayan Müşteriler', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                FocusScope.of(context).unfocus();
                Navigator.pop(context); 
                _searchController.clear();
                ref.read(customerProvider.notifier).clearSearch();

                final selectedCustomerId = await Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (context) => const UnlocatedCustomersScreen())
                );
                
                if (selectedCustomerId != null && selectedCustomerId is String) {
                  _searchController.text = selectedCustomerId;
                  
                  final found = await ref.read(customerProvider.notifier).searchCustomers(selectedCustomerId);
                  if (found != null) {
                    if (found.latitude == 0.0 && _userLocation != null) {
                      _mapController.move(_userLocation!, 16.0);
                    }
                    await Future.delayed(const Duration(milliseconds: 600));
                    _forcePinCurrentLocation(found);
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.verified, color: Colors.green),
              title: const Text('Kayıtlı Müşteriler', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
                
                _searchController.clear();
                ref.read(customerProvider.notifier).clearSearch();

                final selectedCustomerId = await Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (context) => const LocatedCustomersScreen())
                );
                
                if (selectedCustomerId != null && selectedCustomerId is String) {
                  _searchController.text = selectedCustomerId;
                  _performSearch(); 
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Ayarlar'),
              onTap: () {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
                _showSettingsDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Güvenli Çıkış', style: TextStyle(color: Colors.red)),
              onTap: () async {
                FocusScope.of(context).unfocus();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (Route<dynamic> route) => false, 
                );
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userLocation ?? const LatLng(41.0314458, 28.6233605),
              initialZoom: 16.0, 
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.basbug.fieldservice',
                tileProvider: CachedTileProvider(),
                maxZoom: 19,
                minZoom: 3,
                keepBuffer: 3, 
              ),
              MarkerLayer(
                markers: [
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      width: 60, height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.2), 
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent, 
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3.5), 
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                          ),
                        ),
                      ),
                    ),
                ]
              ),
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 45,
                  size: const Size(40, 40),
                  // DİKKAT: Artık customerState.customers değil, customerList kullanıyoruz!
                  markers: customerList.where((c) => c.latitude != 0.0 && c.longitude != 0.0).map((customer) {
                    bool isVerified = _verifiedPins.contains(customer.customerId + customer.latitude.toString());
                    return Marker(
                      point: LatLng(customer.latitude, customer.longitude),
                      width: 60, height: 60,
                      child: GestureDetector(
                        onTap: () => _verifyAndPinLocation(customer),
                        child: Icon(
                          Icons.location_on,
                          color: isVerified ? Colors.green : Colors.grey.shade700,
                          size: 50,
                        ),
                      ),
                    );
                  }).toList(),
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.shade900,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          markers.length.toString(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              maxLines: null, 
                              keyboardType: TextInputType.multiline,
                              decoration: InputDecoration(
                                hintText: 'Müşteri Kodu (Örn: TEST.01.MERKEZ)',
                                border: InputBorder.none,
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          ref.read(customerProvider.notifier).clearSearch();
                                          setState(() {
                                            _selectedAndVerifiedCustomer = null; 
                                          }); 
                                          FocusScope.of(context).unfocus();
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: (value) {
                                if (value.isEmpty) {
                                  ref.read(customerProvider.notifier).clearSearch();
                                  setState(() => _selectedAndVerifiedCustomer = null);
                                } else {
                                  setState(() {});
                                }
                              },
                              onSubmitted: (_) => _performSearch(),
                            ),
                          ),
                          // DİKKAT: Artık customerState.isLoading değil, sadece isLoading!
                          isLoading 
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.search, color: Colors.blueAccent),
                                  onPressed: _performSearch,
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_selectedAndVerifiedCustomer != null)
            Positioned(
              bottom: 30, left: 20, right: 20,
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified, color: Colors.green, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Müşteri: ${_selectedAndVerifiedCustomer!.customerId}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Text(
                        isUnlocated 
                          ? "Bu müşterinin henüz bir konumu yok. Şu an bulunduğunuz canlı konumu bu müşteriye atamak için 'Kaydet' butonuna basın."
                          : "Kirli veri tespit edildi. Veritabanındaki eski koordinatlar, bulunduğunuz canlı ve nokta atışı konum ile değiştirilecektir.",
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  FocusScope.of(context).unfocus();
                                  setState(() {
                                    _selectedAndVerifiedCustomer = null; 
                                    _searchController.clear();
                                  });
                                  ref.read(customerProvider.notifier).clearSearch();
                                },
                                icon: const Icon(Icons.close, color: Colors.black54),
                                label: const Text("İptal", style: TextStyle(color: Colors.black87)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade300,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 45,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  FocusScope.of(context).unfocus();
                                  _showSnackBar("Holding sunucularına iletiliyor...", Colors.orange);
                                  
                                  bool success = await ref.read(customerProvider.notifier).updateAndSyncLocation(
                                    _selectedAndVerifiedCustomer!, 
                                    _userLocation!.latitude,
                                    _userLocation!.longitude,
                                    _resolvedFullAddress ?? "Adres bulunamadı",
                                  );

                                  if (!context.mounted) return; 

                                  if (success) {
                                    _showSnackBar("BAŞARILI: Veriler güncellendi!", Colors.green);
                                    setState(() {
                                      _selectedAndVerifiedCustomer = null; 
                                      _searchController.clear();
                                    });
                                  } else {
                                    _showSnackBar("HATA: İşlem başarısız.", Colors.red);
                                  }
                                },
                                icon: const Icon(Icons.cloud_upload, color: Colors.white),
                                label: const Text("Kaydet", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade900,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          
          // DİKKAT: Artık customerState.errorMessage değil, errorMessage!
          if (errorMessage != null)
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: Card(
                color: Colors.redAccent,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    errorMessage,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue.shade900,
        child: const Icon(Icons.add_location_alt, color: Colors.white),
        onPressed: () {
          TextEditingController newCodeController = TextEditingController();
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Yeni Şube/Müşteri"),
              content: TextField(
                controller: newCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: "Müşteri Kodu / Adı",
                  hintText: "Örn: YENI.01",
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    if (newCodeController.text.isNotEmpty) {
                      String newCode = newCodeController.text.trim().toUpperCase();
                      FocusScope.of(context).unfocus();
                      Navigator.pop(context);
                      
                      CustomerModel dummyNewCustomer = CustomerModel(customerId: newCode, latitude: 0.0, longitude: 0.0);
                      await _forcePinCurrentLocation(dummyNewCustomer);
                    }
                  },
                  child: const Text("Konumlandır"),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}