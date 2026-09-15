// lib/screens/customers/unlocated_customers_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/customer_provider.dart';
import 'dart:async';

class UnlocatedCustomersScreen extends ConsumerStatefulWidget {
  const UnlocatedCustomersScreen({super.key});

  @override
  ConsumerState<UnlocatedCustomersScreen> createState() => _UnlocatedCustomersScreenState();
}

class _UnlocatedCustomersScreenState extends ConsumerState<UnlocatedCustomersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customerState = ref.watch(customerProvider);
    
    // SENİOR DOKUNUŞU: Verileri anlık olarak hem konuma hem de arama çubuğuna göre filtreliyoruz
    final unlocatedList = customerState.customers.where((c) {
      final isUnlocated = c.latitude == 0.0 && c.longitude == 0.0;
      final matchesSearch = c.customerId.toLowerCase().contains(_searchQuery.toLowerCase());
      return isUnlocated && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Konumu Olmayanlar', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        elevation: 1,
      ),
      body: Column(
        children: [
          // 🔎 ANLIK ARAMA ÇUBUĞU
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Müşteri Kodu / Adı Ara...",
                prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = "");
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (value) {
                // Her harfe basıldığında eski sayacı iptal et
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                
                // Kullanıcı yazmayı bitirdikten 300 milisaniye sonra State'i güncelle
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  setState(() => _searchQuery = value.trim());
                });
              },
            ),
          ),
          
          // 📋 MÜŞTERİ LİSTESİ
          Expanded(
            child: unlocatedList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 60, color: Colors.green.shade300),
                        const SizedBox(height: 16),
                        const Text("Harika!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const Text("Bekleyen eksik konumlu müşteri yok.", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: unlocatedList.length,
                    itemBuilder: (context, index) {
                      final customer = unlocatedList[index];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.shade100,
                            child: const Icon(Icons.location_off, color: Colors.redAccent),
                          ),
                          title: Text(customer.customerId, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text("Konum atanmamış. Haritada sabitlemek için dokunun.", style: TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          onTap: () {
                            // Tıklandığında Müşteri ID'sini Harita Ekranına Geri Gönderir
                            Navigator.pop(context, customer.customerId);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}