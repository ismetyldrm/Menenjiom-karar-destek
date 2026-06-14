import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class ReportDetailScreen extends StatefulWidget {
  final int seriesId;
  final String reportContent;

  const ReportDetailScreen({
    super.key,
    required this.seriesId,
    required this.reportContent,
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isSpeaking = false;
  bool _isDoctorVoicePlaying = false;

  @override
  void initState() {
    super.initState();
    _flutterTts.setLanguage("tr-TR");

    // TTS bittiğinde ikonu düzelt
    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });

    // Orijinal ses bittiğinde ikonu düzelt
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) setState(() => _isDoctorVoicePlaying = false);
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- ORİJİNAL DOKTOR SESİNİ ÇALMA (Web ve Windows Uyumlu) ---
  Future<void> _toggleDoctorVoice() async {
    // Eğer TTS konuşuyorsa sustur
    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() => _isSpeaking = false);
    }

    if (_isDoctorVoicePlaying) {
      await _audioPlayer.stop();
      setState(() => _isDoctorVoicePlaying = false);
    } else {
      setState(() => _isDoctorVoicePlaying = true);
      try {
        final response = await http.get(
          Uri.parse(
            'http://localhost:5038/api/AudioReport/series/${widget.seriesId}',
          ),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['audioData'] != null) {
            if (kIsWeb) {
              // WEB İÇİN ÇÖZÜM: BytesSource yerine Data URI kullanıyoruz
              String dataUri = 'data:audio/wav;base64,${data['audioData']}';
              await _audioPlayer.setSourceUrl(dataUri);
              await _audioPlayer.resume();
            } else {
              // WINDOWS/MOBİL İÇİN ÇÖZÜM: Geçici Dosya
              Uint8List audioBytes = base64Decode(data['audioData']);
              final tempDir = await getTemporaryDirectory();
              final tempFile = File(
                '${tempDir.path}${Platform.pathSeparator}detail_${widget.seriesId}.wav',
              );
              await tempFile.writeAsBytes(audioBytes);
              await _audioPlayer.setSourceDeviceFile(tempFile.path);
              await _audioPlayer.resume();
            }
          }
        } else {
          setState(() => _isDoctorVoicePlaying = false);
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
        setState(() => _isDoctorVoicePlaying = false);
        debugPrint("Sesi çalarken hata oluştu: $e");
      }
    }
  }

  // --- YAPAY ZEKA OKUMASI (Gereksiz yerleri atlayarak) ---
  void _toggleTts() async {
    // Eğer orijinal ses çalıyorsa sustur
    if (_isDoctorVoicePlaying) {
      await _audioPlayer.stop();
      setState(() => _isDoctorVoicePlaying = false);
    }

    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() => _isSpeaking = false);
    } else {
      String voiceText = widget.reportContent;

      if (voiceText.contains("BEYİN MR")) {
        voiceText = "Beyin em ar. " + voiceText.split("BEYİN MR").last;
      }
      if (voiceText.contains("Prof. Dr.")) {
        voiceText = voiceText.split("Prof. Dr.").first;
      }

      voiceText = voiceText.replaceAll("-", "").trim();

      setState(() => _isSpeaking = true);
      await _flutterTts.speak(voiceText);
    }
  }

  // --- A4 PDF YAZDIRMA (Türkçe Karakter Destekli) ---
  Future<void> _printThisReport() async {
    final pdf = pw.Document();
    try {
      final fontData = await rootBundle.load(
        "assets/fonts/RobotoMono-Regular.ttf",
      );
      final ttfFont = pw.Font.ttf(fontData);

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
                  "MENENJIOMA AI TIBBI ANALIZ RAPORU",
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 20),
                pw.Text(
                  widget.reportContent,
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.5),
                ),
                pw.Spacer(),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "Rapor No: #${widget.seriesId}",
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      "Sayfa 1 / 1",
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      debugPrint("PDF Yazdırma Hatası: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF161B22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2227),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          "Rapor #${widget.seriesId} Detayı",
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isDoctorVoicePlaying ? Icons.stop : Icons.record_voice_over,
              color: _isDoctorVoicePlaying
                  ? Colors.redAccent
                  : Colors.blueAccent,
            ),
            onPressed: _toggleDoctorVoice,
            tooltip: "Orijinal Sesi Dinle",
          ),
          IconButton(
            icon: Icon(
              _isSpeaking ? Icons.stop : Icons.volume_up,
              color: _isSpeaking ? Colors.redAccent : Colors.white70,
            ),
            onPressed: _toggleTts,
            tooltip: "Yapay Zeka Oku",
          ),
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white70),
            onPressed: _printThisReport,
            tooltip: "Yazdır",
          ),
          const SizedBox(width: 10),
        ],
      ),
      // --- SENİN ORİJİNAL BEYAZ KAĞIT TASARIMIN ---
      body: InteractiveViewer(
        panEnabled: true,
        minScale: 0.5,
        maxScale: 3.0,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Container(
              width: 800,
              padding: const EdgeInsets.all(60),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 20),
                ],
              ),
              child: SelectionArea(
                child: Text(
                  widget.reportContent,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.black,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
