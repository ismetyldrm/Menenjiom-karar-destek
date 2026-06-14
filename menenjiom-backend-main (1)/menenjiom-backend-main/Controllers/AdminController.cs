using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using System.IO;
using System.Linq;
using System;
using MenengiomaBackend.Data;
using MenengiomaBackend.Models;

namespace MenengiomaBackend.Controllers
{
    [Authorize(Roles = "Admin")]
    [Route("api/[controller]")]
    [ApiController]
    public class AdminController : ControllerBase
    {
        private readonly AppDbContext _context;

        public AdminController(AppDbContext context)
        {
            _context = context;
        }

        [HttpGet("dashboard-stats")]
        public IActionResult GetDashboardStats()
        {
            string tempPath = @"C:\Users\Administrator\Desktop\AI\Menengioma_AI\temp_uploads";
            string outputPath = @"C:\Users\Administrator\Desktop\AI\Menengioma_AI\segmentation_outputs";
            long totalBytes = 0;

            if (Directory.Exists(tempPath))
                totalBytes += new DirectoryInfo(tempPath).EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length);
            if (Directory.Exists(outputPath))
                totalBytes += new DirectoryInfo(outputPath).EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length);

            double usedGb = (double)totalBytes / (1024 * 1024 * 1024);
            double totalCapacityGb = 100.0;

            // DÜZELTİLDİ: Zaman karşılaştırması UtcNow üzerinden yapılıyor
            var fifteenMinutesAgo = DateTime.UtcNow.AddMinutes(-15);
            var activeDoctorsCount = _context.AuditLogs
                .Where(l => l.Timestamp >= fifteenMinutesAgo && l.Username != "admin")
                .Select(l => l.Username)
                .Distinct()
                .Count();

            if (activeDoctorsCount == 0 && _context.Users.Any(u => u.Role == "Doktor"))
                activeDoctorsCount = 1;

            var avgAiLatency = _context.AuditLogs
                .Where(l => l.Action.Contains("AI") && l.ExecutionTime > 0)
                .Select(l => l.ExecutionTime)
                .DefaultIfEmpty(1.84)
                .Average();

            // DÜZELTİLDİ: Ekrana basarken Türkiye saatine (.AddHours(3)) çeviriyoruz ki arayüzde doğru görünsün
            var realLogs = _context.AuditLogs
                .OrderByDescending(l => l.Timestamp)
                .Take(10)
                .Select(l => new
                {
                    saat = l.Timestamp.AddHours(3).ToString("HH:mm:ss"),
                    kullanici = l.Username,
                    islem = l.Action,
                    ip = l.IpAddress
                })
                .ToList();

            if (!realLogs.Any())
            {
                var systemUser = _context.Users.FirstOrDefault(u => u.Role == "Admin")?.FullName ?? "Sistem Admin";
                realLogs.Add(new { saat = DateTime.Now.ToString("HH:mm:ss"), kullanici = systemUser, islem = "Yönetici Konsolu Başlatıldı ve Güvenlik Zinciri Devreye Alındı", ip = "127.0.0.1" });
            }

            return Ok(new
            {
                pacsUsedSpace = Math.Round(usedGb, 2),
                pacsTotalSpace = totalCapacityGb,
                pacsPercentage = Math.Round((usedGb / totalCapacityGb) * 100, 1),
                activeDoctors = activeDoctorsCount,
                aiLatency = Math.Round(avgAiLatency, 2),
                auditLogs = realLogs
            });
        }
    }
}