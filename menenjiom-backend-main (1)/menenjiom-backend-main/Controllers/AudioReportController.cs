using MenengiomaBackend.Data;
using MenengiomaBackend.Models;
using MenengiomaBackend.DTOs;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Mvc;
using Google.Cloud.Speech.V1;
using System;
using System.IO;
using System.Threading.Tasks;

namespace MenengiomaBackend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class AudioReportController : ControllerBase
    {
        private readonly AppDbContext _context;

        public AudioReportController(AppDbContext context)
        {
            _context = context;
        }

        [HttpPost]
        public async Task<IActionResult> UploadAudio([FromBody] AudioReportCreateDto request)
        {
            try
            {
                // 1. Flutter'dan gelen Base64 sesi Byte dizisine çevir
                byte[] voiceBytes = Convert.FromBase64String(request.DoctorVoiceData);

                // --- GOOGLE MEDICAL STT İŞLEMİ BAŞLIYOR ---
                string credentialPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "google-creds.json");
                Environment.SetEnvironmentVariable("GOOGLE_APPLICATION_CREDENTIALS", credentialPath);

                var speech = SpeechClient.Create();

                var config = new RecognitionConfig
                {
                    LanguageCode = "tr-TR",
                    // Model olarak tıbbi doğruluk için 'latest_long' iyidir ancak alternatif olarak 'default' da denenebilir.
                    Model = "latest_long",
                    EnableAutomaticPunctuation = true,

                    // Google'a Tıbbi Kelimeleri "Zorunlu" gibi hissettiriyoruz
                    SpeechContexts =
                    {
                        new SpeechContext
                        {
                            Phrases =
                            {
                                "menenjiom", "frontal lob", "sağ frontal", "sol frontal", "dural kuyruk",
                                "ekstraaksiyel", "lezyon", "kitle", "vazojenik ödem", "kontrastlanma",
                                "kalsifikasyon", "atipik menenjiom", "anaplastik", "psammom cisimcikleri",
                                "falks serebri", "parasagital", "konveksite", "sfenoid kanat",
                                "olfaktör oluk", "tüberkülüm sella", "serebellopontin köşe", "klivus",
                                "foramen magnum", "optik sinir kılıfı", "kavernöz sinüs", "tentorium",
                                "kraniyotomi", "rezidü doku", "radyoterapi", "gamma knife", "WHO evre 1",
                                "orta hat şifti", "cerrahiye sevk", "frontal", "parietal", "temporal",
                                "oksipital", "T1A", "T2A", "FLAIR", "IVKM", "TSE-T2", "T1-MPR",
                                "CLARISCAN", "flakon", "paramanyetik"
                            },
                            Boost = 25.0f // Yanlış anlamaları önlemek için Boost değerini biraz daha artırdık.
                        }
                    }
                };

                // --- PLATFORM BAZLI SES FORMATI AYRIMI ---
                if (request.AudioFormat == "wav")
                {
                    config.Encoding = RecognitionConfig.Types.AudioEncoding.Linear16;
                    config.SampleRateHertz = 44100;
                    config.AudioChannelCount = 1;
                }
                else
                {
                    config.Encoding = RecognitionConfig.Types.AudioEncoding.OggOpus;
                    config.SampleRateHertz = 48000;
                    config.AudioChannelCount = 2;
                }

                var audio = RecognitionAudio.FromBytes(voiceBytes);
                var response = speech.Recognize(config, audio);

                string rawTranscript = "";
                foreach (var result in response.Results)
                {
                    rawTranscript += result.Alternatives[0].Transcript;
                }

                // Konsola yazdır ki Google'ın ham halini görebilelim
                Console.WriteLine($"[STT RAW]: {rawTranscript}");

                // 2. VERİTABANI KAYIT KONTROLÜ
                if (request.SeriesID > 0)
                {
                    var audioReport = new AudioReport
                    {
                        SeriesID = request.SeriesID,
                        DoctorVoiceData = voiceBytes,
                        AudioFormat = request.AudioFormat ?? "m4a",
                        CreatedAt = DateTime.UtcNow
                    };

                    _context.AudioReports.Add(audioReport);
                    await _context.SaveChangesAsync();
                }

                // 3. BAŞARI YANITI
                return Ok(new
                {
                    message = request.SeriesID > 0 ? "Ses işlendi ve kaydedildi." : "Ses işlendi (Geçici mod).",
                    transcript = rawTranscript
                });
            }
            catch (Exception ex)
            {
                Console.WriteLine("********** CRITICAL STT ERROR START **********");
                Console.WriteLine(ex.ToString());
                return StatusCode(500, new { message = "Google STT Hatası: " + ex.Message });
            }
        }

        [HttpGet("series/{seriesId}")]
        public async Task<IActionResult> GetAudioBySeriesId(int seriesId)
        {
            try
            {
                var audioReport = await _context.AudioReports.FirstOrDefaultAsync(a => a.SeriesID == seriesId);
                if (audioReport == null || audioReport.DoctorVoiceData == null)
                    return NotFound(new { message = "Bu rapora ait ses kaydı bulunamadı." });

                return Ok(new
                {
                    audioFormat = audioReport.AudioFormat,
                    audioData = Convert.ToBase64String(audioReport.DoctorVoiceData)
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Ses getirilirken hata oluştu: " + ex.Message });
            }
        }
    }
}