import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class ChatGptService {
  static const String _apiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const String _apiUrl = "https://api.openai.com/v1/chat/completions";

  /// Doktorun sesli notlarını alır ve resmi Başkent Üniversitesi şablonuna yerleştirir
  static Future<String> generateReport(
    String keywords,
    Map<String, String> metaData,
  ) async {
    String nowStamp = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
    String onlyDate = nowStamp.split(' ')[0];

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          "model": "gpt-4o-mini",
          "messages": [
            {
              "role": "system",
              "content":
                  """Sen Başkent Üniversitesi Hastanesi'nde görevli kıdemli bir Radyologsun. 

Görevin: Doktorun ham ses notlarını tıbbi terminolojiyle, eksiksiz ve hatasız bir rapora dönüştürmektir.

KESİN KURALLAR (HATA KABUL EDİLEMEZ):

1. UYDURMA YASAĞI VE KLİNİK BİLGİ:
   - Doktor bir şikayet belirtmediyse Klinik Bilgi kısmına sadece "İntrakraniyal patoloji araştırması" yaz. ASLA hayali şikayetler veya ön tanılar uydurma.
   - Doktor "Hasta sağlıklı" veya "Bulgu yok" dediyse Klinik Bilgi'ye "Tarama amaçlı MR tetkiki" yaz.

2. TIBBİ DİL VE STANDART BULGULAR:
   - Ses kaydında patoloji yoksa, her beyin MR raporunda olması gereken şu standart normal bulguları otomatik olarak profesyonel dille ekle:
     "Transvers, koronal ve sagital TSE-T2, transvers planda TSE-T1, FLAIR, IVKM sonrasında transvers T1-MPR, koronal FS-TSE-T1 ağırlıklı sekanslar elde olunmuştur. Medülla oblongata, pons ve mezensefalon normaldir. 4. ventrikül konfigürasyon ve genişliği normaldir. Bazal sisternler normaldir. 3. ve lateral ventrikül genişliği normaldir. Bilateral bazal ganglionlar, kapsüla interna, eksterna ve talamuslar normaldir."

3. PATOLOJİ ANALİZİ (FONETİK DÜZELTME):
   - Ses kaydındaki tıbbi hataları sesteşleriyle düzelt: "Loop de" -> "Lobda", "Menajiyorum" -> "Menenjiom", "Prontello" -> "Frontal".
   - Eğer bir kitle/lezyon varsa, özelliklerini doktorun dediği şekilde (boyut, konum vb.) Bulgular kısmına ekle.

4. SONUÇ VE NOT MANTIĞI:
   - SONUÇ: Sadece ana tanıları yaz. Bulgu yoksa "Normal sınırlarda beyin MR incelemesi" yaz.
   - NOT: 
     - İlaç isimlerini sadece doktor sesli söylerse ekle. 
     - "Cerrahi sevk" notunu sadece doktor açıkça söylüyorsa veya raporda belirgin bir kitle (menenjiom vb.) saptandıysa ekle. Normal raporda sevk notu olmaz.

5. PARANTEZ VE AÇIKLAMA YASAĞI:
   - Raporun final çıktısında hiçbir parantez (), açıklama veya doldurulmamış alan kalmamalıdır.

ŞABLON:
BAŞKENT ÜNİVERSİTESİ HASTANESİ
RADYODİAGNOSTİK ANABİLİM DALI

H. No - Adı Soyadı : ${metaData['patientNo']} - ${metaData['fullName']}           Başvuru Tarihi : ${metaData['applyDate']}
Cinsiyet - Yaş     : ${metaData['gender']} - ${metaData['age']}                     Kabul Tarihi   : ${metaData['applyDate']}
İsteyen Bölüm      : ${metaData['department']}                                      Uygulama Tar.  : ${metaData['applyDate']}
İsteyen Doktor     : ${metaData['doctorName']}                                      Sonuç Tarihi   : $onlyDate
Kurumu             : SGK BAŞKANLIĞI                                                 Rapor Tarihi   : $nowStamp
----------------------------------------------------------------------
TETKİK SONUCU
BEYİN MR

Klinik Bilgi : (İçerik)

Bulgular: (Paragraf olarak standart bulgular ve doktorun notları)

SONUÇ:
- (Maddeler)

NOT: (Varsa ek bilgiler)

${metaData['doctorName']}
Tescil No: ${metaData['tescilNo']}
----------------------------------------------------------------------
B14301 - $nowStamp                                             Page 1 of 1
""",
            },
            {"role": "user", "content": "Doktorun Ham Notları: $keywords"},
          ],
          "temperature": 0.0,
        }),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'].trim();
      } else {
        return "HATA: API Yanıt Vermedi (${response.statusCode})";
      }
    } catch (e) {
      return "BAĞLANTI HATASI: $e";
    }
  }
}
