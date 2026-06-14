using MenengiomaBackend.Data;
using MenengiomaBackend.Models;
using MenengiomaBackend.DTOs;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Authorization;
using System;
using System.Threading.Tasks;

namespace MenengiomaBackend.Controllers
{
    [Authorize]
    [Route("api/[controller]")]
    [ApiController]
    public class PatientController : ControllerBase
    {
        private readonly AppDbContext _context;

        public PatientController(AppDbContext context)
        {
            _context = context;
        }

        [HttpPost]
        public async Task<IActionResult> AddPatient(PatientCreateDto request)
        {
            if (await _context.Patients.AnyAsync(p => p.TCIdentityNo == request.TCIdentityNo))
            {
                return BadRequest("Bu TC Kimlik Numarası ile kayıtlı bir hasta zaten var.");
            }

            var newPatient = new Patient
            {
                TCIdentityNo = request.TCIdentityNo,
                FirstName = request.FirstName,
                LastName = request.LastName,
                BirthDate = request.BirthDate.ToUniversalTime(),
                Gender = request.Gender
            };

            _context.Patients.Add(newPatient);
            await _context.SaveChangesAsync();

            // DÜZELTİLDİ: DateTime.UtcNow yapıldı
            _context.AuditLogs.Add(new AuditLog
            {
                Timestamp = DateTime.UtcNow,
                Username = User.Identity?.Name ?? "Sistem/Doktor",
                Action = $"Yeni Hasta Kaydı Oluşturuldu - TC: {newPatient.TCIdentityNo} ({newPatient.FirstName} {newPatient.LastName})",
                IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "127.0.0.1",
                ExecutionTime = 0
            });
            await _context.SaveChangesAsync();

            return Ok($"Hasta başarıyla eklendi! Hasta ID: {newPatient.PatientID}");
        }

        [HttpGet]
        public async Task<IActionResult> GetAllPatients()
        {
            var patients = await _context.Patients.ToListAsync();

            // DÜZELTİLDİ: DateTime.UtcNow yapıldı
            _context.AuditLogs.Add(new AuditLog
            {
                Timestamp = DateTime.UtcNow,
                Username = User.Identity?.Name ?? "Doktor",
                Action = "Hasta ve Tetkik Listesi Veritabanından Sorgulandı",
                IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "127.0.0.1",
                ExecutionTime = 0
            });
            await _context.SaveChangesAsync();

            return Ok(patients);
        }
    }
}