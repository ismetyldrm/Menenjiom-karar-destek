import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class ReportHistoryScreen extends StatefulWidget {
  final int studyId;
  const ReportHistoryScreen({super.key, required this.studyId});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isSpeaking = false;
  int? _currentlyPlayingTtsId;

  bool _isDoctorVoicePlaying = false;
  int? _currentlyPlayingVoiceId;

  @override
  void initState() {
    super.initState();
    _flutterTts.setLanguage("tr-TR");
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _currentlyPlayingTtsId = null;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _isDoctorVoicePlaying = false;
          _currentlyPlayingVoiceId = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- ORİJİNAL DOKTOR SESİNİ ÇALMA MANTIĞI ---
  Future<void> _toggleDoctorVoice(int seriesId) async {
    // Eğer TTS konuşuyorsa sustur
    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() {
        _isSpeaking = false;
        _currentlyPlayingTtsId = null;
      });
    }

    // Eğer aynı ses çalıyorsa durdur
    if (_isDoctorVoicePlaying && _currentlyPlayingVoiceId == seriesId) {
      await _audioPlayer.stop();
      setState(() {
        _isDoctorVoicePlaying = false;
        _currentlyPlayingVoiceId = null;
      });
    } else {
      // Başka ses çalıyorsa durdur
      await _audioPlayer.stop();
      setState(() {
        _isDoctorVoicePlaying = true;
        _currentlyPlayingVoiceId = seriesId;
      });

      try {
        final response = await http.get(
          Uri.parse('http://localhost:5038/api/AudioReport/series/$seriesId'),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['audioData'] != null) {
            Uint8List audioBytes = base64Decode(data['audioData']);
            if (kIsWeb) {
              await _audioPlayer.play(BytesSource(audioBytes));
            } else {
              // Windows'ta çökme riskine karşı geçici dosyaya yazma tekniği
              final tempDir = await getTemporaryDirectory();
              final tempFile = File(
                '${tempDir.path}/archive_voice_$seriesId.wav',
              );
              await tempFile.writeAsBytes(audioBytes);
              await _audioPlayer.play(DeviceFileSource(tempFile.path));
            }
          }
        } else {
          // Backend'de ses yoksa
          setState(() {
            _isDoctorVoicePlaying = false;
            _currentlyPlayingVoiceId = null;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Orijinal ses kaydı bulunamadı."),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } catch (e) {
        setState(() {
          _isDoctorVoicePlaying = false;
          _currentlyPlayingVoiceId = null;
        });
        debugPrint("Sesi çalarken hata oluştu: $e");
      }
    }
  }

  // --- GELİŞMİŞ TTS: SADECE RAPOR GÖVDESİNİ OKUR ---
  void _toggleTts(int reportId, String content) async {
    // Eğer orijinal ses çalıyorsa durdur
    if (_isDoctorVoicePlaying) {
      await _audioPlayer.stop();
      setState(() {
        _isDoctorVoicePlaying = false;
        _currentlyPlayingVoiceId = null;
      });
    }

    if (_isSpeaking && _currentlyPlayingTtsId == reportId) {
      await _flutterTts.stop();
      setState(() {
        _isSpeaking = false;
        _currentlyPlayingTtsId = null;
      });
    } else {
      await _flutterTts.stop();

      String voiceText = content;

      if (voiceText.contains("BEYİN MR")) {
        voiceText = "Beyin em ar. " + voiceText.split("BEYİN MR").last;
      }

      if (voiceText.contains("Prof. Dr.")) {
        voiceText = voiceText.split("Prof. Dr.").first;
      }

      voiceText = voiceText.replaceAll("-", "").trim();

      setState(() {
        _isSpeaking = true;
        _currentlyPlayingTtsId = reportId;
      });
      await _flutterTts.speak(voiceText);
    }
  }

  Future<List<dynamic>> fetchReports() async {
    try {
      final response = await http.get(
        Uri.parse(
          'http://localhost:5038/api/SeriesFile/study/${widget.studyId}',
        ),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint("Rapor çekme hatası: $e");
    }
    return [];
  }

  // --- TÜRKÇE KARAKTER DESTEKLİ PDF YAZDIRMA ---
  Future<void> _printExistingReport(String fullReportWithMeta) async {
    final pdf = pw.Document();

    String reportContent = fullReportWithMeta.contains("[CONTENT]")
        ? fullReportWithMeta.split("[CONTENT]").last
        : fullReportWithMeta;

    try {
      final fontData = await rootBundle.load(
        "assets/fonts/RobotoMono-Regular.ttf",
      );
      final ttfFont = pw.Font.ttf(fontData);

      List<String> parts = reportContent.split(
        "----------------------------------------------------------------------",
      );
      String header = parts.isNotEmpty ? parts[0] : "";
      String body = parts.length > 1 ? parts[1] : "";
      String footer = parts.length > 2 ? parts[2] : "";

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(35),
          theme: pw.ThemeData.withFont(base: ttfFont),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  header,
                  style: pw.TextStyle(fontSize: 8.5, lineSpacing: 1.1),
                ),
                pw.SizedBox(height: 15),
                pw.Text(
                  body,
                  style: pw.TextStyle(fontSize: 10, lineSpacing: 1.4),
                ),
                pw.Spacer(),
                if (footer.isNotEmpty)
                  pw.Text(
                    footer.split("B16931")[0].trim(),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "Arşiv Kaydı - ${DateFormat('dd/MM/yyyy').format(DateTime.now())}",
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                    pw.Text(
                      "Sayfa 1 / 1",
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(onLayout: (f) async => pdf.save());
    } catch (e) {
      debugPrint("PDF Yazdırma Hatası: $e");
    }
  }

  void _showReportDetail(
    BuildContext context,
    String title,
    String date,
    String content,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2227),
        title: Text(title, style: const TextStyle(color: Colors.tealAccent)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Kayıt Tarihi: $date",
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Divider(color: Colors.white24, height: 20),
              Text(
                content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Kapat",
              style: TextStyle(color: Colors.tealAccent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF161B22),
      appBar: AppBar(
        title: const Text(
          "Rapor Arşivi",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1E2227),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: fetchReports(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "Arşivlenmiş rapor bulunamadı.",
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final sortedReports = snapshot.data!
            ..sort((a, b) => b['seriesID'].compareTo(a['seriesID']));

          return ListView.builder(
            itemCount: sortedReports.length,
            itemBuilder: (context, index) {
              final report = sortedReports[index];
              final int sId = report['seriesID'];
              String fullText = report['aiReportContent'] ?? "";

              String content = fullText.contains("[CONTENT]")
                  ? fullText.split("[CONTENT]").last
                  : fullText;
              String date = fullText.contains("[DATE]")
                  ? fullText.split("[DATE]").last.split("[CONTENT]").first
                  : "Eski Kayıt";

              bool isTtsPlaying = _isSpeaking && _currentlyPlayingTtsId == sId;
              bool isVoicePlaying =
                  _isDoctorVoicePlaying && _currentlyPlayingVoiceId == sId;

              return Card(
                color: const Color(0xFF1E2227),
                margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                child: ListTile(
                  onTap: () =>
                      _showReportDetail(context, "Rapor #$sId", date, content),
                  leading: Icon(
                    Icons.history_edu,
                    color: (isTtsPlaying || isVoicePlaying)
                        ? Colors.redAccent
                        : Colors.tealAccent,
                  ),
                  title: Text(
                    "Rapor #$sId",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    date,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      // Orijinal Ses Oynatma Butonu
                      IconButton(
                        tooltip: "Orijinal Sesi Dinle",
                        icon: Icon(
                          isVoicePlaying ? Icons.stop : Icons.record_voice_over,
                          color: isVoicePlaying
                              ? Colors.redAccent
                              : Colors.blueAccent,
                        ),
                        onPressed: () => _toggleDoctorVoice(sId),
                      ),
                      // Yapay Zeka (TTS) Oynatma Butonu
                      IconButton(
                        tooltip: "Yapay Zeka Okuması",
                        icon: Icon(
                          isTtsPlaying ? Icons.stop : Icons.volume_up,
                          color: isTtsPlaying
                              ? Colors.redAccent
                              : Colors.white70,
                        ),
                        onPressed: () => _toggleTts(sId, content),
                      ),
                      // Yazdırma Butonu
                      IconButton(
                        tooltip: "Yazdır",
                        icon: const Icon(Icons.print, color: Colors.white70),
                        onPressed: () => _printExistingReport(fullText),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
