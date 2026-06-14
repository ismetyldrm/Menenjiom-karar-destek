import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // rootBundle için eklendi
import 'dart:math' as math; // math.pi için eklendi
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';

import '../services/api_service.dart';
import '../services/chatgpt_service.dart';
import '../services/native_audio.dart';
import 'report_history_screen.dart';

class PacsScreen extends StatefulWidget {
  final String patientName;
  final String tcIdentity;
  final String doctorName;
  final String? initialZipPath;
  final int? initialStudyId;

  const PacsScreen({
    super.key,
    required this.patientName,
    required this.tcIdentity,
    required this.doctorName,
    this.initialZipPath,
    this.initialStudyId,
  });

  @override
  State<PacsScreen> createState() => _PacsScreenState();
}

class _PacsScreenState extends State<PacsScreen> {
  double _rotation = 0.0;
  double _brightness = 0.0;
  double _contrast = 1.0;
  bool _isInverted = false;

  int _axialSlice = 75;
  int _sagittalSlice = 120;
  int _coronalSlice = 120;

  final int _maxSliceZ = 154;
  final int _maxSliceX = 239;
  final int _maxSliceY = 239;

  bool _isMprMode = false;
  String? _lastModifiedPlane;

  bool _isAnalyzing = false;
  String? _analysisResult;
  bool _isListening = false;
  bool _isLoadingReport = false;
  bool _isSavingReport = false;
  bool _isSpeaking = false;
  bool _isPlayingOriginal = false;
  String _recognizedWords = "";

  String? _selectedZipPath;
  String? _maskFilePath;
  bool _showAiMask = false;

  String? _lastRecordedFilePath;
  Uint8List? _doctorVoiceBytes;

  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ApiService _apiService = ApiService();
  final TextEditingController _reportController = TextEditingController();
  final ScrollController _reportScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initServices();
    // If caller passed an initial file + study, prefill selections
    if (widget.initialZipPath != null) {
      _selectedZipPath = Uri.encodeComponent(widget.initialZipPath!);
    }
    if (widget.initialStudyId != null) {
      // store if needed later
    }
  }

  void _initServices() async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      try {
        await _speechToText.initialize();
      } catch (e) {
        debugPrint("Yerel STT başlatılamadı: $e");
      }
    }
    await _flutterTts.setLanguage("tr-TR");
  }

  @override
  void dispose() {
    _reportScrollController.dispose();
    _audioPlayer.dispose();
    if (!kIsWeb) NativeAudio.stopAudio();
    _flutterTts.stop();
    super.dispose();
  }

  void _syncSlicesToLastSetCut() {
    if (_selectedZipPath == null) return;
    String plane = _lastModifiedPlane ?? "axial";

    setState(() {
      if (plane == "axial") {
        _sagittalSlice = ((_axialSlice / _maxSliceZ) * _maxSliceX)
            .toInt()
            .clamp(0, _maxSliceX);
        _coronalSlice = ((_axialSlice / _maxSliceZ) * _maxSliceY)
            .toInt()
            .clamp(0, _maxSliceY);
      } else if (plane == "sagittal") {
        _axialSlice = ((_sagittalSlice / _maxSliceX) * _maxSliceZ)
            .toInt()
            .clamp(0, _maxSliceZ);
        _coronalSlice = ((_sagittalSlice / _maxSliceX) * _maxSliceY)
            .toInt()
            .clamp(0, _maxSliceY);
      } else if (plane == "coronal") {
        _axialSlice = ((_coronalSlice / _maxSliceY) * _maxSliceZ)
            .toInt()
            .clamp(0, _maxSliceZ);
        _sagittalSlice = ((_coronalSlice / _maxSliceY) * _maxSliceX)
            .toInt()
            .clamp(0, _maxSliceX);
      }
    });
  }

  Future<void> _printReport() async {
    final String reportText = _reportController.text;
    if (reportText.isEmpty || reportText == "Sizi dinliyorum...") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Yazdırılacak geçerli bir rapor bulunamadı.")),
      );
      return;
    }
    try {
      final fontData =
          await rootBundle.load("assets/fonts/RobotoMono-Regular.ttf");
      final ttfFont = pw.Font.ttf(fontData);
      final pdf = pw.Document();

      List<String> parts = reportText.split(
          "----------------------------------------------------------------------");
      String headerAndMeta = parts.isNotEmpty ? parts[0].trim() : "";
      String findingsAndResults = parts.length > 1 ? parts[1].trim() : "";
      String doctorAndFooter = parts.length > 2 ? parts[2].trim() : "";

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 30),
          theme: pw.ThemeData.withFont(base: ttfFont),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(headerAndMeta,
                    style: pw.TextStyle(fontSize: 8.5, lineSpacing: 1.1)),
                pw.SizedBox(height: 15),
                pw.Text(findingsAndResults,
                    style: pw.TextStyle(fontSize: 10, lineSpacing: 1.4)),
                pw.Spacer(),
                pw.Text(doctorAndFooter.split("B16931")[0].trim(),
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                        "B16931 ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}",
                        style: const pw.TextStyle(fontSize: 7)),
                    pw.Text("Sayfa 1 / 1",
                        style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
              ],
            );
          },
        ),
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Radyoloji_Raporu_${widget.patientName.replaceAll(' ', '_')}',
      );
    } catch (e) {
      debugPrint("Yazdırma Hatası: $e");
    }
  }

  void _toggleListening() async {
    if (!_isListening) {
      try {
        setState(() {
          _recognizedWords = "";
          _reportController.text = "Sizi dinliyorum...";
          _isListening = true;
          _lastRecordedFilePath = null;
        });
        if (!kIsWeb) await NativeAudio.startRecording();
        if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
          bool available = await _speechToText.initialize();
          if (available) {
            await _speechToText.listen(
              localeId: "tr_TR",
              onResult: (result) {
                setState(() {
                  _recognizedWords = result.recognizedWords;
                  _reportController.text = _recognizedWords;
                });
              },
            );
          }
        }
      } catch (e) {
        setState(() {
          _isListening = false;
          _reportController.text = "HATA: Mikrofon başlatılamadı ($e)";
        });
      }
    } else {
      try {
        if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
          await _speechToText.stop();
        }
        String? returnedPath;
        if (!kIsWeb) returnedPath = await NativeAudio.stopRecording();
        setState(() => _isListening = false);

        if (returnedPath != null) {
          _lastRecordedFilePath = returnedPath;
          await Future.delayed(const Duration(milliseconds: 1000));
          final audioFile = File(returnedPath);
          if (await audioFile.exists()) {
            final bytes = await audioFile.readAsBytes();
            if (bytes.length > 1000) {
              _doctorVoiceBytes = bytes;
              _processVoiceAndGenerateReport();
            } else {
              setState(() => _reportController.text = "Hata: Ses verisi boş.");
            }
          }
        }
      } catch (e) {
        setState(() {
          _isListening = false;
          _reportController.text = "HATA: Kayıt durdurulamadı ($e)";
        });
      }
    }
  }

  Future<void> _processVoiceAndGenerateReport() async {
    setState(() => _isLoadingReport = true);
    String bestTranscript = _recognizedWords.trim();
    String audioFormat = kIsWeb ? "webm" : "wav";

    if (_doctorVoiceBytes != null) {
      try {
        final sttResponse = await http.post(
          Uri.parse('http://localhost:5038/api/AudioReport'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            "seriesID": 0,
            "doctorVoiceData": base64Encode(_doctorVoiceBytes!),
            "audioFormat": audioFormat,
          }),
        );
        if (sttResponse.statusCode == 200) {
          final sttData = jsonDecode(sttResponse.body);
          if (sttData['transcript'] != null &&
              sttData['transcript'].toString().trim().isNotEmpty) {
            bestTranscript = sttData['transcript'];
          }
        }
      } catch (e) {
        debugPrint("Backend bağlantı hatası: $e");
      }
    }

    bool hasSpeech =
        bestTranscript.isNotEmpty && bestTranscript != "Sizi dinliyorum...";
    bool hasAiData =
        _analysisResult != null && _analysisResult!.contains("TÜMÖR");

    if (!hasSpeech && !hasAiData) {
      setState(() {
        _isLoadingReport = false;
        _reportController.text =
            "Rapor oluşturmak için lütfen mikrofona konuşun veya MR analizi yapın.";
      });
      return;
    }

    String chatGptPrompt = "";
    if (hasSpeech) {
      chatGptPrompt += "Radyoloğun Sesli Notu: $bestTranscript\n\n";
    } else {
      chatGptPrompt +=
          "Radyolog sesli not bırakmadı. Sadece aşağıdaki sayısal bulguları kullanarak raporu yaz.\n\n";
    }

    if (hasAiData) {
      chatGptPrompt +=
          "Görüntü İşleme Yapay Zeka Sonuçları:\n$_analysisResult\n"
          "Lütfen bu hacim değerlerini raporun 'Bulgular' kısmına mutlaka dahil et ve 'Sonuç' kısmında hastada Menenjiom ile uyumlu kitle tespit edildiğini belirten patolojik bir rapor yaz.";
    } else {
      chatGptPrompt +=
          "Lütfen sadece radyoloğun sesli notuna dayanarak standart bir radyoloji raporu oluştur.";
    }

    Map<String, String> reportMeta = {
      "patientNo": "4832XX",
      "fullName": widget.patientName,
      "tcNo": widget.tcIdentity,
      "gender": "Erkek",
      "age": "36 Yıl",
      "department": "Beyin ve Sinir Cerrahisi",
      "doctorName": widget.doctorName,
      "tescilNo": "172060",
      "applyDate": DateFormat('dd/MM/yyyy').format(DateTime.now()),
    };

    try {
      String aiReport =
          await ChatGptService.generateReport(chatGptPrompt, reportMeta);
      setState(() {
        _reportController.text = aiReport;
        _isLoadingReport = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingReport = false;
        _reportController.text = "HATA: Yapay zeka raporu oluşturulamadı.";
      });
    }
  }

  void _playOriginalVoice() async {
    if (_isPlayingOriginal) {
      if (!kIsWeb) await NativeAudio.stopAudio();
      setState(() => _isPlayingOriginal = false);
    } else {
      if (!kIsWeb && _lastRecordedFilePath != null) {
        File audioFile = File(_lastRecordedFilePath!);
        if (await audioFile.exists()) {
          setState(() => _isPlayingOriginal = true);
          await NativeAudio.playAudio(_lastRecordedFilePath!);
          Future.delayed(const Duration(seconds: 10), () {
            if (mounted) setState(() => _isPlayingOriginal = false);
          });
        }
      }
    }
  }

  void _toggleTts() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() => _isSpeaking = false);
    } else {
      String fullReport = _reportController.text;
      if (fullReport.isNotEmpty && fullReport != "Sizi dinliyorum...") {
        String voiceText = fullReport.contains("TETKİK SONUCU")
            ? fullReport.split("TETKİK SONUCU").last
            : fullReport;
        if (voiceText.contains(widget.doctorName)) {
          voiceText = voiceText.split(widget.doctorName).first;
        }
        setState(() => _isSpeaking = true);
        voiceText = voiceText.replaceAll("-", "").trim();
        await _flutterTts.speak(voiceText);
        _flutterTts
            .setCompletionHandler(() => setState(() => _isSpeaking = false));
      }
    }
  }

  Future<void> _handleConfirmReport() async {
    if (_reportController.text.length < 20) return;
    setState(() => _isSavingReport = true);
    String nowStamp = DateFormat('dd.MM.yyyy - HH:mm').format(DateTime.now());
    String reportWithDate = "[DATE]$nowStamp[CONTENT]${_reportController.text}";
    try {
      final response = await http.post(
        Uri.parse('http://localhost:5038/api/SeriesFile'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          "studyID": 1,
          "aiReportContent": reportWithDate,
          "filePath_Original": "C:/Storage/Original.nii",
          "filePath_Mask": _maskFilePath ?? "C:/Storage/Mask.nii",
          "tumorVolume": 55.79,
          "isProcessed": true,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        int seriesId = jsonDecode(response.body)['seriesID'];
        if (_doctorVoiceBytes != null) {
          String audioFormat = kIsWeb ? "webm" : "wav";
          await http.post(
            Uri.parse('http://localhost:5038/api/AudioReport'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              "seriesID": seriesId,
              "doctorVoiceData": base64Encode(_doctorVoiceBytes!),
              "audioFormat": audioFormat,
            }),
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Rapor Arşivlendi!"),
              backgroundColor: Colors.green),
        );
      }
    } finally {
      setState(() => _isSavingReport = false);
    }
  }

  void _resetImage() => setState(() {
        _rotation = 0.0;
        _brightness = 0.0;
        _contrast = 1.0;
        _isInverted = false;
        _axialSlice = 75;
        _sagittalSlice = 120;
        _coronalSlice = 120;
        _showAiMask = false;
        _isMprMode = false;
        _lastModifiedPlane = null;
      });

  List<double> get _colorMatrix {
    if (_isInverted) {
      return [
        -1,
        0,
        0,
        0,
        255,
        0,
        -1,
        0,
        0,
        255,
        0,
        0,
        -1,
        0,
        255,
        0,
        0,
        0,
        1,
        0,
      ];
    }
    double t = (1.0 - _contrast) / 2.0 * 255.0;
    return [
      _contrast,
      0,
      0,
      0,
      _brightness * 255 + t,
      0,
      _contrast,
      0,
      0,
      _brightness * 255 + t,
      0,
      0,
      _contrast,
      0,
      _brightness * 255 + t,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  String _buildSliceUrl(int slice, String plane) {
    String url =
        'http://127.0.0.1:5001/api/get_slice/$slice?zip_path=$_selectedZipPath&show_mask=$_showAiMask&plane=$plane';
    if (_maskFilePath != null && _maskFilePath!.isNotEmpty) {
      url += '&mask_path=$_maskFilePath';
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2227),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          tooltip: "Hasta Listesine Geri Dön",
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.patientName,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 2),
            Text(
              "ID: ${widget.tcIdentity} | Axial: $_axialSlice | Sagittal: $_sagittalSlice | Coronal: $_coronalSlice",
              style: const TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: Row(
        children: [
          // ----------------------------------------------------
          // SOL ARAÇ ÇUBUĞU (TOOLBAR)
          // ----------------------------------------------------
          Container(
            width: 60,
            color: const Color(0xFF1E2227),
            child: Column(
              children: [
                _buildToolIcon(
                  _isMprMode
                      ? Icons.splitscreen_rounded
                      : Icons.dashboard_rounded,
                  _isMprMode ? "Tekli Ekrana Dön" : "MPR 3'lü Ekran Modu",
                  () => setState(() {
                    _isMprMode = !_isMprMode;
                  }),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Divider(color: Colors.white24),
                ),
                _buildToolIcon(
                  Icons.rotate_90_degrees_cw,
                  "Döndür",
                  () => setState(() => _rotation += math.pi / 2),
                ),
                _buildToolIcon(
                  Icons.brightness_6,
                  "Parlaklık",
                  () => setState(
                      () => _brightness = (_brightness + 0.1).clamp(-1.0, 1.0)),
                ),
                _buildToolIcon(
                  Icons.contrast,
                  "Kontrast",
                  () => setState(
                      () => _contrast = (_contrast + 0.5).clamp(0.0, 4.0)),
                ),
                _buildToolIcon(
                  Icons.invert_colors,
                  "Invert Filters",
                  () => setState(() => _isInverted = !_isInverted),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Divider(color: Colors.white24, thickness: 1),
                ),
                Tooltip(
                  message: "Yapay Zeka Maskesi",
                  child: InkWell(
                    onTap: _maskFilePath == null
                        ? null
                        : () => setState(() => _showAiMask = !_showAiMask),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Icon(
                        _showAiMask ? Icons.layers : Icons.layers_clear,
                        color: _maskFilePath == null
                            ? Colors.white12
                            : (_showAiMask
                                ? Colors.tealAccent
                                : Colors.grey[400]),
                        size: 26,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                _buildToolIcon(Icons.refresh, "Sıfırla", _resetImage),
              ],
            ),
          ),

          // ----------------------------------------------------
          // ORTA KISIM: GÖRÜNTÜ ALANI VE DİNAMİK MPR MATRİSİ
          // ----------------------------------------------------
          Expanded(
            child: Container(
              color: Colors.black,
              child: _isMprMode
                  ? Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: _buildMprThreeQuadView(),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: _buildSingleView("axial", _axialSlice),
                          ),
                        ),
                        Slider(
                          value: _axialSlice.toDouble(),
                          min: 0,
                          max: _maxSliceZ.toDouble(),
                          activeColor: Colors.tealAccent,
                          onChanged: _selectedZipPath == null
                              ? null
                              : (v) => setState(() {
                                    _axialSlice = v.toInt();
                                    _lastModifiedPlane = "axial";
                                  }),
                        ),
                      ],
                    ),
            ),
          ),

          // ----------------------------------------------------
          // SAĞ PANEL: YAPAY ZEKA VE RAPORLAMA ASİSTANI
          // ----------------------------------------------------
          Container(
            width: 350,
            color: const Color(0xFF1E2227),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "AI Analiz Asistanı",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _isAnalyzing
                      ? null
                      : () async {
                          String? filePath = widget.initialZipPath;
                          int studyId = widget.initialStudyId ?? 1;

                          // If no initial file passed, let user pick one
                          if (filePath == null) {
                            FilePickerResult? result =
                                await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['zip'],
                              withData: true,
                            );

                            if (result == null) return;

                            final pickedFile = result.files.single;
                            final bytes = pickedFile.bytes;
                            final name = pickedFile.name;

                            if (bytes != null) {
                              // web or bytes-only upload: make zip available to slice server before preview
                              var uploadResult = await _apiService.uploadZip(bytes, name);
                              if (uploadResult == null || uploadResult['zip_path'] == null) {
                                setState(() {
                                  _isAnalyzing = false;
                                  _analysisResult = "ZIP sunucuya yüklenemedi.";
                                });
                                return;
                              }

                              filePath = uploadResult['zip_path'];
                              setState(() {
                                _selectedZipPath = Uri.encodeComponent(filePath!);
                                _maskFilePath = null;
                                _showAiMask = false;
                                _isAnalyzing = true;
                                _analysisResult = null;
                              });

                              var aiResponse = await _apiService.analyzeMri(
                                  studyId, null,
                                  fileBytes: bytes, filename: name);

                              setState(() {
                                _isAnalyzing = false;
                                if (aiResponse != null && aiResponse.containsKey('message')) {
                                  try {
                                    var data = aiResponse['data'];
                                    var isMeningioma = data['is_meningioma'] == true;
                                    var maskPath = data['mask_file_path'];
                                    var vols = data['volumes_cm3'];

                                    if (isMeningioma) {
                                      if (maskPath != null) {
                                        _maskFilePath = Uri.encodeComponent(maskPath.toString());
                                      }
                                      if (vols != null) {
                                        _analysisResult =
                                            "MENENGIOMA TESPİT EDİLDİ\n\n"
                                            "Nekrotik Çekirdek: ${vols['ncr']} cm³\n"
                                            "Ödem (Edema): ${vols['ed']} cm³\n"
                                            "Aktif Tümör: ${vols['et']} cm³\n"
                                            "Toplam Hacim: ${vols['total_wt']} cm³";
                                      } else {
                                        _analysisResult =
                                            "Meningiom tespit edildi fakat hacim bilgisi alınamadı.";
                                      }
                                    } else {
                                      _maskFilePath = null;
                                      _analysisResult =
                                          data['message'] ??
                                              "Meningiom bulgusu bulunamadı. Segmentasyon yapılmadı.";
                                    }
                                  } catch (e) {
                                    _analysisResult = "JSON Okuma Hatası.";
                                  }
                                } else {
                                  _analysisResult =
                                      "Hata: Sunucudan beklenen veri formatı gelmedi.";
                                }
                              });

                              return;
                            } else if (!kIsWeb && pickedFile.path != null) {
                              filePath = pickedFile.path;
                            } else {
                              return;
                            }
                          }

                          setState(() {
                            _selectedZipPath = Uri.encodeComponent(filePath!);
                            _maskFilePath = null;
                            _showAiMask = false;
                            _isAnalyzing = true;
                            _analysisResult = null;
                          });

                          var aiResponse = await _apiService.analyzeMri(studyId, filePath!);

                          setState(() {
                            _isAnalyzing = false;
                            if (aiResponse != null && aiResponse.containsKey('message')) {
                              try {
                                var data = aiResponse['data'];
                                var isMeningioma = data['is_meningioma'] == true;
                                var maskPath = data['mask_file_path'];
                                var vols = data['volumes_cm3'];

                                if (isMeningioma) {
                                  if (maskPath != null) {
                                    _maskFilePath = Uri.encodeComponent(maskPath.toString());
                                  }
                                  if (vols != null) {
                                    _analysisResult =
                                        "MENENGIOMA TESPİT EDİLDİ\n\n"
                                        "Nekrotik Çekirdek: ${vols['ncr']} cm³\n"
                                        "Ödem (Edema): ${vols['ed']} cm³\n"
                                        "Aktif Tümör: ${vols['et']} cm³\n"
                                        "Toplam Hacim: ${vols['total_wt']} cm³";
                                  } else {
                                    _analysisResult =
                                        "Meningiom tespit edildi fakat hacim bilgisi alınamadı.";
                                  }
                                } else {
                                  _maskFilePath = null;
                                  _analysisResult =
                                      data['message'] ??
                                          "Meningiom bulgusu bulunamadı. Segmentasyon yapılmadı.";
                                }
                              } catch (e) {
                                _analysisResult = "JSON Okuma Hatası.";
                              }
                            } else {
                              _analysisResult =
                                  "Hata: Sunucudan beklenen veri formatı gelmedi.";
                            }
                          });
                        },
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(_isAnalyzing
                      ? "Analiz Ediliyor..."
                      : "MR SEÇ VE ANALİZ ET"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                ),
                if (_analysisResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: _analysisResult!.contains("Hata")
                        ? Colors.red.withAlpha(26)
                        : Colors.green.withAlpha(26),
                    child: Text(_analysisResult!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, height: 1.5)),
                  ),
                ],
                const Divider(height: 20, color: Colors.white24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Sesli Raporlama",
                        style: TextStyle(
                            color: Colors.tealAccent,
                            fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                const ReportHistoryScreen(studyId: 1)),
                      ),
                      icon: const Icon(Icons.history,
                          color: Colors.tealAccent, size: 16),
                      label: const Text("Geçmiş",
                          style: TextStyle(color: Colors.tealAccent)),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 40,
                      onPressed: _isLoadingReport ? null : _toggleListening,
                      icon: CircleAvatar(
                        backgroundColor:
                            _isListening ? Colors.red : Colors.teal,
                        child: Icon(_isListening ? Icons.stop : Icons.mic,
                            color: Colors.white),
                      ),
                    ),
                    if (_lastRecordedFilePath != null ||
                        (kIsWeb && _doctorVoiceBytes != null)) ...[
                      const SizedBox(width: 15),
                      IconButton(
                        iconSize: 30,
                        onPressed: _isLoadingReport ? null : _playOriginalVoice,
                        icon: CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Icon(
                              _isPlayingOriginal
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RawScrollbar(
                        controller: _reportScrollController,
                        thumbColor: Colors.tealAccent,
                        radius: const Radius.circular(10),
                        thickness: 6,
                        thumbVisibility: true,
                        interactive: true,
                        child: TextField(
                          controller: _reportController,
                          scrollController: _reportScrollController,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          enabled: !_isLoadingReport,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontFamily: 'monospace',
                              height: 1.5),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black45,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Colors.tealAccent),
                            ),
                            contentPadding: const EdgeInsets.all(15),
                          ),
                        ),
                      ),
                      if (_isLoadingReport)
                        Container(
                          decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12)),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                    color: Colors.tealAccent),
                                SizedBox(height: 15),
                                Text("Yapay Zeka Raporu Oluşturuyor...",
                                    style: TextStyle(
                                        color: Colors.tealAccent,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _toggleTts,
                        child: Text(_isSpeaking ? "Durdur" : "Dinle"),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _printReport,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey),
                        child: const Text("Yazdır"),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_isLoadingReport || _isSavingReport)
                            ? null
                            : _handleConfirmReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          disabledBackgroundColor: Colors.green.withAlpha(76),
                        ),
                        child: _isSavingReport
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text("Onayla",
                                style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- SADELEŞTİRİLMİŞ 3'LÜ MPR TASARIMI ---
  Widget _buildMprThreeQuadView() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D21),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.monitor_rounded,
                      color: Colors.tealAccent, size: 14),
                  SizedBox(width: 6),
                  Text("Multi-Planar Reconstruction (MPR) - 3'lü Görünüm",
                      style: TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade900,
                  foregroundColor: Colors.tealAccent,
                  side: const BorderSide(color: Colors.tealAccent, width: 1),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.link_rounded, size: 14),
                label: const Text("Görüntüleri Son Ayarlanan Kesite Eşitle",
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _syncSlicesToLastSetCut,
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              // SOL TARAF: BÜYÜK AXIAL GÖRÜNTÜ
              Expanded(
                flex: 1,
                child: _buildQuadrantItem(
                  plane: "axial",
                  title: "AXIAL (ÜSTTEN GÖRÜNÜM)",
                  color: Colors.red,
                  currentSlice: _axialSlice,
                  maxSlice: _maxSliceZ,
                  onSliceChanged: (v) => setState(() {
                    _axialSlice = v;
                    _lastModifiedPlane = "axial";
                  }),
                ),
              ),
              const SizedBox(width: 8),
              // SAĞ TARAF: ALT ALTA SAGITTAL VE CORONAL GÖRÜNTÜLER
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    Expanded(
                      child: _buildQuadrantItem(
                        plane: "sagittal",
                        title: "SAGITTAL (YANDAN GÖRÜNÜM)",
                        color: Colors.amber.shade700,
                        currentSlice: _sagittalSlice,
                        maxSlice: _maxSliceX,
                        onSliceChanged: (v) => setState(() {
                          _sagittalSlice = v;
                          _lastModifiedPlane = "sagittal";
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _buildQuadrantItem(
                        plane: "coronal",
                        title: "CORONAL (ÖNDEN GÖRÜNÜM)",
                        color: Colors.green,
                        currentSlice: _coronalSlice,
                        maxSlice: _maxSliceY,
                        onSliceChanged: (v) => setState(() {
                          _coronalSlice = v;
                          _lastModifiedPlane = "coronal";
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuadrantItem({
    required String plane,
    required String title,
    required Color color,
    required int currentSlice,
    required int maxSlice,
    required ValueChanged<int> onSliceChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(153), width: 1.5),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 8, right: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.black.withAlpha(178),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
                Text("Kesit: $currentSlice",
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: _buildSingleView(plane, currentSlice),
            ),
          ),
          SizedBox(
            height: 24,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: color,
                inactiveTrackColor: color.withAlpha(38),
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: currentSlice.toDouble(),
                min: 0,
                max: maxSlice.toDouble(),
                onChanged: _selectedZipPath == null
                    ? null
                    : (v) => onSliceChanged(v.toInt()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleView(String plane, int sliceIndex) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          ColorFiltered(
            colorFilter: ColorFilter.matrix(_colorMatrix),
            child: _selectedZipPath == null
                ? const Center(
                    child: Text("MR Yüklenmedi",
                        style: TextStyle(color: Colors.white30, fontSize: 13)),
                  )
                : Image.network(
                    _buildSliceUrl(sliceIndex, plane),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
          ),
          if (_selectedZipPath != null) ..._buildCompassLabels(plane),
        ],
      ),
    );
  }

  List<Widget> _buildCompassLabels(String plane) {
    String top = "A", bottom = "P", left = "R", right = "L";
    if (plane == "sagittal") {
      top = "S";
      bottom = "I";
      left = "A";
      right = "P";
    }
    if (plane == "coronal") {
      top = "S";
      bottom = "I";
      left = "R";
      right = "L";
    }

    TextStyle style = const TextStyle(
        color: Colors.amberAccent,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(color: Colors.black, blurRadius: 4)]);
    return [
      Positioned(top: 15, child: Text(top, style: style)),
      Positioned(bottom: 2, child: Text(bottom, style: style)),
      Positioned(left: 6, child: Text(left, style: style)),
      Positioned(right: 6, child: Text(right, style: style)),
    ];
  }

  Widget _buildToolIcon(IconData icon, String tooltip, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            child: Icon(
              icon,
              color: (_isMprMode && icon == Icons.splitscreen_rounded)
                  ? Colors.tealAccent
                  : Colors.grey[400],
              size: 26,
            ),
          ),
        ),
      );
}
