import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:5038/api';

  /// Kullanıcı adı ve şifre ile giriş yapar ve gelen JWT Token'ı saklar.
  Future<Map<String, dynamic>?> login(String username, String password) async {
    try {
      var uri = Uri.parse('$baseUrl/Auth/login');
      var response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: json.encode({'username': username, 'password': password}),
      );

      var responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        var responseData = json.decode(response.body);

        if (responseData['token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          // 1. Token'ı kaydediyoruz
          await prefs.setString('jwt_token', responseData['token']);

          // 2. KESİNLİKLE BU SATIRI EKLEYİN: Backend'den gelen rolü hafızaya atıyoruz
          await prefs.setString('user_role', responseData['role'] ?? 'Doktor');
        }
        return responseData;
      } else {
        print('Giriş Başarısız: ${responseData['message']}');
        return responseData;
      }
    } catch (e) {
      print('Bağlantı Hatası: $e');
      return {"message": "Sunucuya bağlanılamadı."};
    }
  }

  /// Yeni kullanıcı kayıt işlemi. (Sadece Admin yetkisiyle çalışır)
  Future<Map<String, dynamic>?> register(
      String username, String password, String fullName, String email) async {
    try {
      // 1. Giriş yapmış olan Admin'in kartını (token) hafızadan alıyoruz
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      var uri = Uri.parse('$baseUrl/Auth/register');
      var response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          if (token != null)
            "Authorization":
                "Bearer $token" // <--- Admin olduğunu backend'e kanıtlıyor
        },
        body: json.encode({
          'username': username,
          'password': password,
          'fullName': fullName,
          'email': email
        }),
      );

      var responseData = json.decode(response.body);
      if (response.statusCode == 200) {
        return {
          "status": "success",
          "message": responseData['message'] ?? "Kayıt başarılı!"
        };
      } else {
        return {
          "status": "error",
          "message": responseData['message'] ??
              "Kayıt başarısız. Yetkiniz olmayabilir."
        };
      }
    } catch (e) {
      return {"status": "error", "message": "Sunucuya bağlanılamadı."};
    }
  }

  /// ZIP dosyasını gönderir ve token ile yetkilendirme yapar.
  Future<Map<String, dynamic>?> analyzeMri(
      int seriesId, String? filePath,
      {Uint8List? fileBytes, String? filename}) async {
    try {
      // 1. Cihazdaki kartı (token) al
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      var uri = Uri.parse('$baseUrl/SeriesFile/$seriesId/analyze');
      var request = http.MultipartRequest('POST', uri);

      // 2. Kapı görevlisine (Backend) kartını göster
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      if (fileBytes != null) {
        // web or caller provided bytes
        request.files.add(http.MultipartFile.fromBytes(
          'mriZipFile',
          fileBytes,
          filename: filename ?? 'upload.zip',
          contentType: MediaType('application', 'zip'),
        ));
      } else if (filePath != null) {
        if (kIsWeb) {
          throw Exception('Web üzerinde dosya yolundan analiz desteklenmiyor. Lütfen ZIP dosyasını tekrar seçin.');
        }
        request.files.add(await http.MultipartFile.fromPath('mriZipFile', filePath));
      } else {
        throw Exception('No file provided for analyzeMri');
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Yetkisiz erişim veya hata: ${response.statusCode} -> ${response.body}');
        try {
          return json.decode(response.body);
        } catch (_) {
          return {
            'status': 'error',
            'message': 'Sunucu hatası: ${response.statusCode}'
          };
        }
      }
    } catch (e) {
      print('Bağlantı Hatası: $e');
      return null;
    }
  }
  Future<Map<String, dynamic>?> uploadZip(Uint8List bytes, String filename) async {
    var uri = Uri.parse('http://localhost:5001/api/upload_zip');
    var request = http.MultipartRequest('POST', uri);
    request.files.add(http.MultipartFile.fromBytes(
      'zip_file',
      bytes,
      filename: filename,
      contentType: MediaType('application', 'zip'),
    ));
    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    return response.statusCode == 200 ? json.decode(response.body) : null;
  }

  Future<Map<String, dynamic>?> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/Auth/forgot-password'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email}),
      );
      return response.statusCode == 200
          ? jsonDecode(response.body)
          : {"status": "error", "message": "Hata: ${response.statusCode}"};
    } catch (e) {
      return {"status": "error", "message": "Bağlantı hatası."};
    }
  }

  Future<Map<String, dynamic>?> resetPassword(
      String email, String token, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/Auth/reset-password'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(
            {"email": email, "token": token, "newPassword": newPassword}),
      );
      return response.statusCode == 200
          ? jsonDecode(response.body)
          : jsonDecode(response.body);
    } catch (e) {
      return {"status": "error", "message": "Bağlantı hatası."};
    }
  }
}
