import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import 'pacs_screen.dart';
import 'login_screen.dart'; // YENİ EKLENEN IMPORT: Çıkış yapınca yönlendirmek için

// --- HASTA LİSTESİ VE ADMİN YÖNETİM EKRANI ---
class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  List<dynamic> realPatients = [];
  bool isLoading = true;
  String userRole = 'Doktor';

  // --- CANLI DASHBOARD DEĞİŞKENLERİ ---
  double pacsUsedSpace = 0.0;
  double pacsTotalSpace = 100.0;
  double pacsPercentage = 0.0;
  int activeDoctors = 0;
  double aiLatency = 1.84;
  List<dynamic> liveAuditLogs = [];

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userRole = prefs.getString('user_role') ?? 'Doktor';
    });

    if (userRole == 'Admin') {
      await fetchDashboardData();
      setState(() => isLoading = false);
    } else {
      await fetchPatients();
    }
  }

  Future<void> fetchDashboardData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      final response = await http.get(
        Uri.parse('http://localhost:5038/api/Admin/dashboard-stats'),
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token"
        },
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          pacsUsedSpace = (data['pacsUsedSpace'] as num).toDouble();
          pacsTotalSpace = (data['pacsTotalSpace'] as num).toDouble();
          pacsPercentage = (data['pacsPercentage'] as num).toDouble();
          activeDoctors = (data['activeDoctors'] as num).toInt();
          aiLatency = (data['aiLatency'] as num).toDouble();
          liveAuditLogs = data['auditLogs'];
        });
      }
    } catch (e) {
      print("Canlı dashboard verisi çekilemedi.");
    }
  }

  Future<void> fetchPatients() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      final response = await http.get(
        Uri.parse('http://localhost:5038/api/Patient'),
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token"
        },
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        setState(() {
          realPatients = json.decode(response.body);
          if (realPatients.isEmpty) {
            _insertDummyData();
          }
          isLoading = false;
        });
      } else {
        _handleError();
      }
    } catch (e) {
      _handleError();
    }
  }

  void _handleError() {
    setState(() {
      _insertDummyData();
      isLoading = false;
    });
  }

  void _insertDummyData() {
    realPatients = [
      {
        'tcIdentityNo': '12345678901',
        'firstName': 'DENEME',
        'lastName': 'HASTASI',
        'gender': 'Erkek',
        'birthDate': '1990-03-17T00:00:00Z',
      },
    ];
  }

  void _showAddDoctorDialog() {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_add_alt_1, color: Colors.teal),
            SizedBox(width: 10),
            Text("Sisteme Yeni Doktor Tanımla"),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: fullNameController,
                  decoration: const InputDecoration(
                      labelText: 'Ad Soyad', prefixIcon: Icon(Icons.badge)),
                  validator: (v) =>
                      v!.isEmpty ? 'Bu alan boş bırakılamaz' : null,
                ),
                TextFormField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                      labelText: 'Kullanıcı Adı',
                      prefixIcon: Icon(Icons.account_circle)),
                  validator: (v) =>
                      v!.isEmpty ? 'Bu alan boş bırakılamaz' : null,
                ),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                      labelText: 'E-posta Adresi',
                      prefixIcon: Icon(Icons.email)),
                  validator: (v) =>
                      v!.isEmpty ? 'Bu alan boş bırakılamaz' : null,
                ),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Geçici Şifre', prefixIcon: Icon(Icons.lock)),
                  validator: (v) =>
                      v!.length < 4 ? 'Şifre en az 4 karakter olmalıdır' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("İptal", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final result = await ApiService().register(
                  usernameController.text.trim(),
                  passwordController.text.trim(),
                  fullNameController.text.trim(),
                  emailController.text.trim(),
                );

                if (context.mounted) {
                  Navigator.pop(context);
                  if (result != null && result['status'] == 'success') {
                    await fetchDashboardData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Doktor başarıyla sisteme tanımlandı!'),
                          backgroundColor: Colors.green),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(result?['message'] ??
                              'Kayıt işlemi başarısız oldu.'),
                          backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            child: const Text("Kaydet", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  Future<void> _pickAndAddPatient() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true, 
    );

    if (result != null) {
      final pickedFile = result.files.single;
      
      // --- 1. YENİ: DOSYAYI ANINDA PYTHON'A YÜKLE ---
      // PACS ekranındaki siyah alanın dolması için dosyayı hemen Python'a atıyoruz
      var uploadResult = await ApiService().uploadZip(pickedFile.bytes!, pickedFile.name);
      String? pythonZipPath;
      if (uploadResult != null && uploadResult['zip_path'] != null) {
        pythonZipPath = uploadResult['zip_path'];
      } else {
        debugPrint("HATA: Python sunucusuna yüklenemedi!");
      }

      String cleanFileName = pickedFile.name.replaceAll('.zip', '');

      // --- 2. ADIM: Etik kurul gereği varsayılanlar (C# DTO kurallarına uygun) ---
      String finalPatientName = "Anonim Hasta $cleanFileName";
      String finalTc = "11111111111"; // Tam 11 hane
      String finalGender = "E";       // C# MaxLength(1) kuralı için "Belirtilmemiş" yerine "E"
      String finalBirthDate = "01.01.1990";

      // --- 3. ADIM: Kısmi Anonimlik Filtresi ---
      Map<String, dynamic>? backendData = {
         "PatientName": "", 
         "PatientID": null,
         "PatientSex": "K",
         "PatientBirthDate": "15.05.1985"
      };

      if (backendData != null) {
        if (backendData['PatientName'] != null && backendData['PatientName'].toString().trim().isNotEmpty) {
          finalPatientName = backendData['PatientName'];
        }
        if (backendData['PatientID'] != null && backendData['PatientID'].toString().trim().length == 11) {
          finalTc = backendData['PatientID']; 
        }
        if (backendData['PatientSex'] != null && backendData['PatientSex'].toString().trim().isNotEmpty) {
          finalGender = backendData['PatientSex'].toString().substring(0, 1).toUpperCase(); 
        }
        if (backendData['PatientBirthDate'] != null && backendData['PatientBirthDate'].toString().trim().isNotEmpty) {
          finalBirthDate = backendData['PatientBirthDate'];
        }
      }

      // --- 4. ADIM: C# BACKEND (SQL) İÇİN VERİ FORMATLAMA VE API İSTEĞİ ---
      // A. İsimleri Ad ve Soyad olarak ayırma (Listede null null çıkmasını engeller)
      List<String> nameParts = finalPatientName.split(' ');
      String firstName = nameParts.first;
      String lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : "";

      // B. Tarihi C# DateTime formatına çevirme (dd.MM.yyyy -> yyyy-MM-dd)
      String formattedDate = "1990-01-01T00:00:00Z";
      try {
        List<String> dateParts = finalBirthDate.split('.');
        if (dateParts.length == 3) {
          formattedDate = "${dateParts[2]}-${dateParts[1]}-${dateParts[0]}T00:00:00Z";
        }
      } catch(e) {}

      // C. Veritabanına Kayıt İsteği Atma
      try {
        final prefs = await SharedPreferences.getInstance();
        String? token = prefs.getString('jwt_token');

        var response = await http.post(
          Uri.parse('http://localhost:5038/api/Patient'),
          headers: {
            "Content-Type": "application/json",
            if (token != null) "Authorization": "Bearer $token"
          },
          body: json.encode({
            "TCIdentityNo": finalTc,
            "FirstName": firstName,
            "LastName": lastName,
            "BirthDate": formattedDate,
            "Gender": finalGender
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint("C# Backend: Hasta SQL veritabanına başarıyla kaydedildi.");
        } else {
          debugPrint("C# Backend Uyarısı: ${response.body}");
        }
      } catch (e) {
        debugPrint("C# Backend'e ulaşılamadı: $e");
      }

      // --- 5. ADIM: Arayüz listesini güncelle ve Görüntüleri Hafızaya Al ---
      setState(() {
        realPatients.insert(0, {
          'tcIdentity': finalTc,
          'firstName': firstName, 
          'lastName': lastName,
          'fullName': finalPatientName,
          'gender': finalGender,
          'birthDate': finalBirthDate,
          'zipPath': pythonZipPath,     // Geri dönüşte resimleri tekrar açmak için
          'zipBytes': pickedFile.bytes, // Yapay zeka analiz butonu için
          'fileName': pickedFile.name,
          'maskPath': null,
          'analysisResult': null,
        });
      });

      if (!mounted) return;
      
      // --- 6. ADIM: PACS ekranına geçiş yap ---
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PacsScreen(
            patientName: finalPatientName,
            tcIdentity: finalTc,
            doctorName: "Dr. Kullanıcı", 
            initialZipPath: pythonZipPath, // Artık dosya ismini değil, Python'dan gelen GERÇEK yolu veriyoruz!
            initialZipBytes: pickedFile.bytes, 
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Row(
          children: [
            Icon(
              userRole == 'Admin'
                  ? Icons.admin_panel_settings
                  : Icons.table_chart_outlined,
              color: Colors.teal,
            ),
            const SizedBox(width: 10),
            Text(
              userRole == 'Admin'
                  ? "Sistem Yönetim Paneli (IT)"
                  : "Tetkik Listesi",
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 15),
            ),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text("Güvenli Çıkış",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear(); // Token ve Rol bilgisini temizle
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : userRole == 'Admin'
              ? _buildAdminDashboard()
              : _buildPatientList(),
      
      // --- YENİ EKLENEN KISIM: SAĞ ALT YÜKLEME BUTONU ---
      // Sadece admin olmayanlar (doktorlar vb.) bu butonu görebilir
      floatingActionButton: userRole != 'Admin' 
          ? FloatingActionButton.extended(
              onPressed: _pickAndAddPatient, // Bir önceki adımda yazdığımız fonksiyonu çağırır
              backgroundColor: Colors.teal,
              icon: const Icon(Icons.add_to_drive, color: Colors.white),
              label: const Text(
                "Yeni Hasta MR Yükle",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  // --- ADMİN PANELİ ARAYÜZÜ ---
  Widget _buildAdminDashboard() {
    return Padding(
      padding: const EdgeInsets.all(25.0),
      key: const ValueKey("AdminPanel"),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "PACS & AI Altyapı İzleme",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A202C)),
                  ),
                  SizedBox(height: 4),
                  Text(
                      "Sistem durumu, medikal veri depolama hacmi ve KVKK erişim denetimi.",
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _showAddDoctorDialog,
                icon: const Icon(Icons.person_add_alt_1,
                    color: Colors.white, size: 20),
                label: const Text("Yeni Doktor Tanımla",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("PACS DICOM Depolama Hacmi",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                          Icon(Icons.storage_rounded,
                              color: Colors.teal, size: 20),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                          "${pacsUsedSpace.toStringAsFixed(2)} GB / ${pacsTotalSpace.toStringAsFixed(0)} GB",
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3748))),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: (pacsPercentage / 100).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade100,
                          color: pacsPercentage > 85 ? Colors.red : Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text("%$pacsPercentage Kapasite Kullanımı",
                          style: TextStyle(
                              color: pacsPercentage > 85
                                  ? Colors.red
                                  : Colors.teal,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("AI Pipeline (MONAI Core)",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                          Icon(Icons.memory_rounded,
                              color: Colors.blue, size: 20),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text("Ort. ${aiLatency.toStringAsFixed(2)} Saniye",
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3748))),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: Colors.green, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          const Text("GPU Giriş-Çıkış Aktif (CUDA)",
                              style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Aktif Klinik Oturumlar",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                          Icon(Icons.supervised_user_circle_rounded,
                              color: Colors.indigo, size: 20),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text("$activeDoctors Aktif Doktor",
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3748))),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text("Tüm Bağlantılar JWT Korumalı",
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          const Text(
            "Sistem Güvenlik ve Veri Erişim Logları (KVKK Denetim İzleri)",
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3748)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: liveAuditLogs.isEmpty
                    ? const Center(child: Text("Henüz sistem logu bulunmuyor."))
                    : ListView.separated(
                        itemCount: liveAuditLogs.length,
                        separatorBuilder: (context, index) =>
                            Divider(height: 1, color: Colors.grey.shade100),
                        itemBuilder: (context, index) {
                          final log = liveAuditLogs[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                Text(log["saat"] ?? "--:--:--",
                                    style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                        fontFamily: 'monospace')),
                                const SizedBox(width: 25),
                                SizedBox(
                                  width: 180,
                                  child: Text(
                                    log["kullanici"] ?? "Bilinmeyen",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF4A5568),
                                        fontSize: 13),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    log["islem"] ?? "-",
                                    style: const TextStyle(
                                        color: Colors.black87, fontSize: 13),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(
                                    log["ip"] ?? "127.0.0.1",
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 11,
                                        fontFamily: 'monospace'),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- DOKTOR PANELİ (HASTA LİSTESİ ARAYÜZÜ) ---
  Widget _buildPatientList() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      key: const ValueKey("PatientList"),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: "TC Kimlik No veya Hasta Adı ile ara...",
              prefixIcon: const Icon(Icons.search, color: Colors.teal),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: const BoxDecoration(
              color: Colors.teal,
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text("TC KİMLİK NO",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold))),
                Expanded(
                    flex: 3,
                    child: Text("AD SOYAD",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold))),
                Expanded(
                    flex: 1,
                    child: Text("CİNSİYET",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold))),
                Expanded(
                    flex: 2,
                    child: Text("DOĞUM TARİHİ",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold))),
                Expanded(
                    flex: 1,
                    child: Icon(Icons.settings, color: Colors.white, size: 18)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(10)),
              ),
              child: ListView.separated(
                itemCount: realPatients.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: Colors.grey),
                itemBuilder: (context, index) {
                  final patient = realPatients[index];

                  String formattedDate = "01.01.1990";
                  if (patient['birthDate'] != null) {
                    try {
                      DateTime parsedDate =
                          DateTime.parse(patient['birthDate'].toString());
                      formattedDate =
                          "${parsedDate.day.toString().padLeft(2, '0')}.${parsedDate.month.toString().padLeft(2, '0')}.${parsedDate.year}";
                    } catch (e) {
                      formattedDate = "Tarih Yok";
                    }
                  }

                  return InkWell(
                    onTap: () {
                      String tc =
                          (patient['tcIdentityNo'] ?? "12345678901").toString();
                      String fName =
                          (patient['firstName'] ?? "DENEME").toString();
                      String lName =
                          (patient['lastName'] ?? "HASTASI").toString();

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PacsScreen(
                            patientName: "$fName $lName".trim(),
                            tcIdentity: tc,
                            doctorName: "Prof. Dr. Fatma Şule Geredelioğlu",
                            initialZipPath: patient['zipPath'], 
                            initialZipBytes: patient['zipBytes'],
                            initialZipFilename: patient['fileName'],
                            initialMaskPath: patient['maskPath'],
                            initialAnalysisResult: patient['analysisResult'],
                            onAnalysisCompleted: (mask, result) {
                              setState(() {
                                patient['maskPath'] = mask;
                                patient['analysisResult'] = result;
                              });
                            },
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 15),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 2,
                              child: Text(
                                  patient['tcIdentityNo']?.toString() ?? "-",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87))),
                          Expanded(
                              flex: 3,
                              child: Text(
                                  "${patient['firstName']} ${patient['lastName']}",
                                  style:
                                      const TextStyle(color: Colors.black87))),
                          Expanded(
                              flex: 1,
                              child: Text(
                                  patient['gender']?.toString().toUpperCase() ??
                                      "E",
                                  style:
                                      const TextStyle(color: Colors.black87))),
                          Expanded(
                              flex: 2,
                              child: Text(formattedDate,
                                  style:
                                      const TextStyle(color: Colors.black54))),
                          Expanded(
                              flex: 1,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                IconButton(
                                  tooltip: 'Hastayı Kalıcı Olarak Sil',
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text("Hastayı Sistemden Sil"),
                                        content: Text("${patient['firstName']} ${patient['lastName']} isimli hastayı sistemden kalıcı olarak silmek istediğinize emin misiniz?"),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text("İptal", style: TextStyle(color: Colors.grey)),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                            
                                            // --- VERİTABANINDAN SİLME İŞLEMİ BURADA BAŞLIYOR ---
                                            onPressed: () async {
                                              // 1. Ekrandan anında sil (Kullanıcıyı bekletmemek için)
                                              setState(() {
                                                realPatients.removeAt(index); 
                                              });
                                              Navigator.pop(context); // Onay penceresini kapatır

                                              // 2. C# Backend'den (SQL Veritabanı) Kalıcı Olarak Sil
                                              int? pId = patient['patientID'] ?? patient['patientId'];
                                              if (pId != null) {
                                                try {
                                                  final prefs = await SharedPreferences.getInstance();
                                                  String? token = prefs.getString('jwt_token');
                                                  
                                                  await http.delete(
                                                    Uri.parse('http://localhost:5038/api/Patient/$pId'),
                                                    headers: {
                                                      "Content-Type": "application/json",
                                                      if (token != null) "Authorization": "Bearer $token"
                                                    },
                                                  );
                                                } catch (e) {
                                                  debugPrint("Veritabanından silinirken hata oluştu: $e");
                                                }
                                              }
                                            },
                                            // --------------------------------------------------
                                            
                                            child: const Text("Kalıcı Sil", style: TextStyle(color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey)
                              ])),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadAndAnalyze(Map patient, String? filePath,
      {Uint8List? fileBytes, String? filename}) async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt_token');

    int patientId = 0;
    if (patient.containsKey('patientID')) {
      patientId = patient['patientID'];
    } else if (patient.containsKey('patientId')) {
      patientId = patient['patientId'];
    } else {
      // Try fallback: no patient id available
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Hasta ID bulunamadı. Lütfen önce hasta oluşturun.'),
          backgroundColor: Colors.red));
      return;
    }

    // 1) Create a new Study for this patient
    try {
      final studyReq = {
        'patientID': patientId,
        'studyDate': DateTime.now().toUtc().toIso8601String(),
        'modality': 'MR',
        'status': 'NEW',
        'accessionNumber': ''
      };

      await http.post(Uri.parse('http://localhost:5038/api/Study'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token'
          },
          body: json.encode(studyReq));

      // 2) Fetch studies for patient and pick latest StudyID
      final studiesRes = await http.get(
          Uri.parse('http://localhost:5038/api/Study/patient/$patientId'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token'
          });

      if (studiesRes.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Çekimler alınamadı.'), backgroundColor: Colors.red));
        return;
      }

      final studiesList = json.decode(studiesRes.body) as List<dynamic>;
      if (studiesList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Çekim oluşturulamadı.'), backgroundColor: Colors.red));
        return;
      }

      final latest = studiesList.last;
      int studyId = latest['studyID'] ?? latest['StudyID'] ?? 0;

        // 3) Call AI analyze endpoint with created studyId and either path or bytes
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Analiz başlatılıyor...'), backgroundColor: Colors.teal));

        String? selectedZipPath = filePath;
        if (fileBytes != null && filename != null) {
          var uploadResult = await ApiService().uploadZip(fileBytes, filename);
          if (uploadResult == null || uploadResult['zip_path'] == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('ZIP sunucuya yüklenemedi.'),
                backgroundColor: Colors.red));
            return;
          }
          selectedZipPath = uploadResult['zip_path'];
        }

        await ApiService().analyzeMri(studyId, filePath,
            fileBytes: fileBytes, filename: filename);

        // 4) Navigate to PACS screen with file preselected (for native) or study only (web)
        String fName = (patient['firstName'] ?? '').toString();
        String lName = (patient['lastName'] ?? '').toString();
        String tc = (patient['tcIdentityNo'] ?? '').toString();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PacsScreen(
              patientName: "$fName $lName".trim(),
              tcIdentity: tc,
              doctorName: "Prof. Dr. Fatma Şule Geredelioğlu",
              initialZipPath: selectedZipPath ?? filePath,
              initialZipBytes: fileBytes,
              initialZipFilename: filename,
              initialStudyId: studyId,
              initialMaskPath: patient['maskPath'],
              initialAnalysisResult: patient['analysisResult'],
              onAnalysisCompleted: (mask, result) {
                setState(() {
                  patient['maskPath'] = mask;
                  patient['analysisResult'] = result;
                  patient['zipPath'] = selectedZipPath ?? filePath; // Dosyayı da tut
                  patient['zipBytes'] = fileBytes; // Dosyayı da tut
                });
              },
            ),
          ),
        );
      } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Yükleme/analiz hatası: $e'),
          backgroundColor: Colors.red));
    }
  }
}
