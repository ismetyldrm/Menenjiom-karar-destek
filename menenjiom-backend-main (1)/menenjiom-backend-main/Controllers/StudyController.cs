using MenengiomaBackend.Data;
using MenengiomaBackend.Models;
using MenengiomaBackend.DTOs;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace MenengiomaBackend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class StudyController : ControllerBase
    {
        private readonly AppDbContext _context;

        public StudyController(AppDbContext context)
        {
            _context = context;
        }

        // 1. Yeni MR Çekimi Ekleme
        [HttpPost]
        public async Task<IActionResult> AddStudy(StudyCreateDto request)
        {
            // ÖNEMLİ: Önce veritabanında gerçekten böyle bir hasta var mı diye bakıyoruz!
            var patientExists = await _context.Patients.AnyAsync(p => p.PatientID == request.PatientID);
            if (!patientExists)
            {
                return NotFound("Hata: Belirtilen ID'ye sahip bir hasta bulunamadı!");
            }

            var newStudy = new Study
            {
                PatientID = request.PatientID, // MR'ı hastaya bağlıyoruz
                StudyDate = request.StudyDate.ToUniversalTime(), // Saat krizini önlemek için UTC yapıyoruz
                Modality = request.Modality,
                Status = request.Status,
                AccessionNumber = request.AccessionNumber
            };

            _context.Studies.Add(newStudy);
            await _context.SaveChangesAsync();

            return Ok(new { studyId = newStudy.StudyID, message = $"MR Çekimi başarıyla eklendi! Çekim ID: {newStudy.StudyID}, Hasta ID: {newStudy.PatientID}" });
        }

        // 2. Belirli Bir Hastanın Tüm MR'larını Getirme
        [HttpGet("patient/{patientId}")]
        public async Task<IActionResult> GetStudiesByPatient(int patientId)
        {
            // Sadece bizim istediğimiz hastanın ID'sine sahip çekimleri filtreleyip getirir
            var studies = await _context.Studies
                .Where(s => s.PatientID == patientId)
                .ToListAsync();

            if (!studies.Any())
            {
                return NotFound("Bu hastaya ait herhangi bir MR çekimi bulunamadı.");
            }

            return Ok(studies);
        }
    }
}