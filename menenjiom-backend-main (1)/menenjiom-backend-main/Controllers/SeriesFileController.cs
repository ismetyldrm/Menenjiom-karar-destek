using MenengiomaBackend.Data;
using MenengiomaBackend.Models;
using MenengiomaBackend.DTOs;
using MenengiomaBackend.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Http;

namespace MenengiomaBackend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class SeriesFileController : ControllerBase
    {
        private readonly AppDbContext _context;
        private readonly AiIntegrationService _aiService;

        public SeriesFileController(AppDbContext context, AiIntegrationService aiService)
        {
            _context = context;
            _aiService = aiService;
        }

        [HttpPost]
        public async Task<IActionResult> AddSeriesFile(SeriesFileCreateDto request)
        {
            var studyExists = await _context.Studies.AnyAsync(s => s.StudyID == request.StudyID);
            if (!studyExists)
            {
                return NotFound(new { message = "Hata: Belirtilen ID'ye sahip bir MR çekimi bulunamadı!" });
            }

            var newSeriesFile = new SeriesFile
            {
                StudyID = request.StudyID,
                AiReportContent = request.AiReportContent,
                FilePath_Original = request.FilePath_Original,
                FilePath_Mask = request.FilePath_Mask,
                TumorVolume = request.TumorVolume,
                IsProcessed = request.IsProcessed
            };

            _context.SeriesFiles.Add(newSeriesFile);
            await _context.SaveChangesAsync();

            return Ok(new
            {
                seriesID = newSeriesFile.SeriesID,
                message = "Dosya kaydı başarıyla eklendi!"
            });
        }

        [HttpGet("study/{studyId}")]
        public async Task<IActionResult> GetFilesByStudy(int studyId)
        {
            var files = await _context.SeriesFiles
                .Where(f => f.StudyID == studyId)
                .ToListAsync();

            if (!files.Any())
            {
                return NotFound(new { message = "Bu MR çekimine ait herhangi bir dosya kaydı bulunamadı." });
            }

            return Ok(files);
        }

        [HttpPost("{studyId}/analyze")]
        public async Task<IActionResult> AnalyzeAndSaveAiReport(int studyId, IFormFile mriZipFile)
        {
            if (mriZipFile == null || mriZipFile.Length == 0)
                return BadRequest(new { message = "Lütfen analiz için geçerli bir DICOM ZIP dosyası yükleyin." });

            var newSeriesFile = new SeriesFile
            {
                StudyID = studyId,
                FilePath_Original = mriZipFile.FileName,
                IsProcessed = false 
            };

            _context.SeriesFiles.Add(newSeriesFile);
            await _context.SaveChangesAsync();

            try
            {
                var aiResult = await _aiService.AnalyzeMriAsync(mriZipFile);
                bool isMeningioma = aiResult?.Is_meningioma == true;

                if (aiResult != null){
                    Console.WriteLine("AI başarılı bir şekilde analiz etti");
                }

                if (isMeningioma && aiResult?.Volumes_cm3 != null)
                {
                    newSeriesFile.TumorVolume = (float)aiResult.Volumes_cm3.Total_wt;
                    newSeriesFile.FilePath_Mask = aiResult.Mask_file_path;
                    newSeriesFile.IsProcessed = true;

                    newSeriesFile.AiReportContent = $"Otomatik Analiz Sonucu: Nekrotik Çekirdek {aiResult.Volumes_cm3.Ncr} cm³, " +
                                                     $"Ödem {aiResult.Volumes_cm3.Ed} cm³, Aktif Tümör {aiResult.Volumes_cm3.Et} cm³.";
                }
                else
                {
                    newSeriesFile.IsProcessed = true;
                    newSeriesFile.AiReportContent = aiResult?.Is_meningioma == false
                        ? "Meningiom bulgusu bulunamadı. Segmentasyon yapılmadı."
                        : "Analiz tamamlandı ancak meningiom veya segmentasyon sonuçları elde edilemedi.";
                }

                _context.SeriesFiles.Update(newSeriesFile);
                await _context.SaveChangesAsync();

                return Ok(new
                {
                    status = "success",
                    message = isMeningioma
                        ? "Yapay zeka analizi başarıyla tamamlandı."
                        : "Yapay zeka analizi tamamlandı. Menengiom bulgusu bulunamadı.",
                    series_id = newSeriesFile.SeriesID,
                    data = new
                    {
                        is_meningioma = isMeningioma,
                        predicted_class = aiResult?.Predicted_class,
                        confidence = aiResult?.Confidence ?? 0,
                        is_ood = aiResult?.Is_ood ?? false,
                        mask_file_path = aiResult?.Mask_file_path,
                        volumes_cm3 = isMeningioma ? new
                        {
                            ncr = aiResult?.Volumes_cm3?.Ncr ?? 0,
                            ed = aiResult?.Volumes_cm3?.Ed ?? 0,
                            et = aiResult?.Volumes_cm3?.Et ?? 0,
                            total_wt = aiResult?.Volumes_cm3?.Total_wt ?? 0
                        } : null
                    }
                });
            }
            catch (Exception ex)
            {
                newSeriesFile.AiReportContent = $"Analiz Hatası: {ex.Message}";
                _context.SeriesFiles.Update(newSeriesFile);
                await _context.SaveChangesAsync();
                Console.WriteLine("AI analizinde sıkıntı var");

                return StatusCode(500, new { message = $"AI Sunucusu ile iletişim hatası: {ex.Message}" });
            }
        }
    }
}