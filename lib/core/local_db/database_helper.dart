// lib/core/local_db/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../../models/customer_model.dart';
import '../utils/app_logger.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('CustomerGeo.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    final exists = await databaseExists(path);

    if (!exists) {
      AppLogger.info("Veritabanı kopyalanıyor...");
      try {
        await Directory(dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load(join('assets/db', filePath));
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
        AppLogger.info("Veritabanı başarıyla kopyalandı.");
      } catch (e) {
        AppLogger.error("Veritabanı kopyalama hatası: $e");
      }
    }

    return await openDatabase(
      path,
      onOpen: (db) async {
        // --- SENİOR DOKUNUŞU: TABLO ŞEMASINI ANALİZ ET ---
        // Bu kod, hazır veritabanındaki sütunları terminale basar ki bir daha kör uçuşu yapmayalım.
        try {
          final tableInfo = await db.rawQuery('PRAGMA table_info(CustomerLocations)');
          AppLogger.info("TABLO ŞEMASI: $tableInfo");
        } catch(e) {
          AppLogger.error("Tablo şeması okunamadı.");
        }

        await db.execute('''
          CREATE TABLE IF NOT EXISTS SyncQueue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerCode TEXT,
            latitude REAL,
            longitude REAL,
            address TEXT,
            status TEXT
          )
        ''');
        
       // --- 2. GÜVENLİ TEST VERİSİ EKLEME ---
        try {
          final result = await db.query('CustomerLocations', where: 'CustomerCode = ?', whereArgs: ['TEST.01.MERKEZ']);
          if (result.isEmpty) {
            await db.insert('CustomerLocations', {
              'CustomerCode': 'TEST.01.MERKEZ',
              'Title': 'Başbuğ Holding Merkez Test', // DÜZELTME: CustomerName yerine Title!
              'Latitude': 41.0314458, 
              'Longitude': 28.6233605,
              'ResolutionLevel': 2, // DÜZELTME: Metin yerine Tam Sayı (Integer)!
              'GeocodeStatus': 1,    // DÜZELTME: Onay durumu için veritabanındaki gerçek sütun!
              'CreatedDate': DateTime.now().toIso8601String()
            });
            AppLogger.info("Holding Merkez test müşterisi başarıyla eklendi veya zaten mevcut.");
          }
        } catch (e) {
          AppLogger.error(" 🔥 Test müşterisi eklenirken hata: $e");
        }
      },
    );
  }

  // --- ARAMA İŞLEMİ (Zırhlı Çeviri ve Hata Koruması) ---
  Future<List<CustomerModel>> getCustomersById(String id) async {
    final db = await instance.database;
    try {
      final maps = await db.query(
        'CustomerLocations', 
        where: 'UPPER(CustomerCode) = ?',
        whereArgs: [id.toUpperCase().trim()],
      );
      
      if (maps.isNotEmpty) {
        return maps.map((e) {
          // SENİOR DOKUNUŞU: Veritabanından String veya Null gelse bile çökmesini engelliyoruz!
          double lat = 0.0;
          double lng = 0.0;
          
          if (e['Latitude'] != null) lat = double.tryParse(e['Latitude'].toString()) ?? 0.0;
          if (e['Longitude'] != null) lng = double.tryParse(e['Longitude'].toString()) ?? 0.0;
          
          return CustomerModel(
            customerId: e['CustomerCode']?.toString() ?? '',
            latitude: lat,
            longitude: lng,
          );
        }).toList();
      }
      return [];
    } catch (e) {
      AppLogger.error("VERİTABANI ARAMA HATASI: $e");
      return [];
    }
  }

  // --- 3. MANUEL UPSERT (NULL ve Çoklu Şube Koruması) ---
  Future<int> updateCustomerLocationLocally(String customerCode, double oldLat, double oldLng, double newLat, double newLng) async {
    final db = await instance.database;
    try {
      String whereClause;
      List<dynamic> whereArgs;

      // SENİOR DOKUNUŞU: Veritabanında "0" veya "NULL" olma durumunu güvenle yakalıyoruz
      if (oldLat == 0.0 && oldLng == 0.0) {
        whereClause = 'UPPER(CustomerCode) = ? AND (Latitude IS NULL OR Latitude = 0 OR Latitude = 0.0)';
        whereArgs = [customerCode.toUpperCase().trim()];
      } else {
        whereClause = 'UPPER(CustomerCode) = ? AND Latitude = ? AND Longitude = ?';
        whereArgs = [customerCode.toUpperCase().trim(), oldLat, oldLng];
      }

      int changes = await db.update(
        'CustomerLocations',
        {
          'Latitude': newLat,
          'Longitude': newLng,
          'GeocodeStatus': 1, // Güncellendiğini belirtmek için
        },
        where: whereClause,
        whereArgs: whereArgs,
      );

      if (changes == 0) {
        return await db.insert(
          'CustomerLocations',
          {
            'CustomerCode': customerCode.toUpperCase().trim(),
            'Title': 'Yeni Şube / Müşteri', 
            'Latitude': newLat,
            'Longitude': newLng,
            'ResolutionLevel': 2, 
            'GeocodeStatus': 1,
            'CreatedDate': DateTime.now().toIso8601String()
          },
        );
      }
      return changes; 
    } catch (e) {
      AppLogger.error("YENİ LOKASYON GÜNCELLEME HATASI: $e");
      return 0;
    }
  }

  Future<int> insertToSyncQueue(String customerCode, double lat, double lng, String address) async {
    final db = await instance.database;
    return await db.insert('SyncQueue', {
      'customerCode': customerCode.toUpperCase(),
      'latitude': lat,
      'longitude': lng,
      'address': address,
      'status': 'PENDING'
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSyncs() async {
    final db = await instance.database;
    return await db.query('SyncQueue', where: 'status = ?', whereArgs: ['PENDING']);
  }

  Future<int> removeFromSyncQueue(int id) async {
    final db = await instance.database;
    return await db.delete('SyncQueue', where: 'id = ?', whereArgs: [id]);
  }

  // --- EKLENEN YENİ METOD: PLASİYERE GÖRE MÜŞTERİ LİSTESİ ---
  // YÖNETİCİ SUNUMU İÇİN (Geçici): Excel'den aktarılan PlasiyerMusterileri tablosunu okur
  // ve CustomerLocations tablosundaki koordinatlarla birleştirip (JOIN) döndürür.
 // --- SENİOR DOKUNUŞU: YÜKSEK PERFORMANSLI VE GÜVENLİ SORGULAMA ---
  Future<List<CustomerModel>> getCustomersBySalDept(String salDeptCode) async {
    final db = await instance.database;
    try {
      // 1. TRIM ve UPPER ile kirli verileri temizleyip eşleştiriyoruz.
      // 2. LEFT JOIN sayesinde plasiyerin müşterisi CustomerLocations'da hiç olmasa bile listeye gelir (Konumu Yok olarak).
      final maps = await db.rawQuery('''
        SELECT 
          p.CUSTOMER as CustomerCode,
          c.Latitude,
          c.Longitude
        FROM PlasiyerMusterileri p
        LEFT JOIN CustomerLocations c ON TRIM(UPPER(p.CUSTOMER)) = TRIM(UPPER(c.CustomerCode))
        WHERE TRIM(p.SALDEPT) = ?
      ''', [salDeptCode.trim()]);

      AppLogger.info("$salDeptCode kodlu plasiyer için ${maps.length} müşteri bulundu.");

      if (maps.isNotEmpty) {
        return maps.map((e) {
          double lat = 0.0;
          double lng = 0.0;
          
          if (e['Latitude'] != null) {
            lat = double.tryParse(e['Latitude'].toString()) ?? 0.0;
          }
          if (e['Longitude'] != null) {
            lng = double.tryParse(e['Longitude'].toString()) ?? 0.0;
          }

          return CustomerModel(
            customerId: e['CustomerCode'].toString().trim(),
            latitude: lat,
            longitude: lng,
          );
        }).toList();
      }
      return [];
    } catch (e) {
      AppLogger.error("Plasiyer müşterileri çekilirken DB HATASI: $e");
      return [];
    }
  }
}