using MenengiomaBackend.Data;
using MenengiomaBackend.Models;
using MenengiomaBackend.DTOs;
using MenengiomaBackend.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Authorization;
using System;
using System.Threading.Tasks;

namespace MenengiomaBackend.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class AuthController : ControllerBase
    {
        private readonly AppDbContext _context;
        private readonly EmailService _emailService;
        private readonly TokenService _tokenService;

        public AuthController(AppDbContext context, EmailService emailService, TokenService tokenService)
        {
            _context = context;
            _emailService = emailService;
            _tokenService = tokenService;
        }

        [HttpPost("register")]
        [Authorize(Roles = "Admin")]
        public async Task<IActionResult> Register(UserRegisterDto request)
        {
            if (await _context.Users.AnyAsync(u => u.Username == request.Username))
            {
                return BadRequest(new { message = "Bu kullanıcı adı zaten alınmış." });
            }

            string salt = BCrypt.Net.BCrypt.GenerateSalt(12);
            string securePasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password, salt);

            var user = new User
            {
                Username = request.Username,
                PasswordHash = securePasswordHash,
                FullName = request.FullName,
                Email = request.Email,
                Role = "Doktor"
            };

            _context.Users.Add(user);
            await _context.SaveChangesAsync();

            // DÜZELTİLDİ: DateTime.UtcNow yapıldı
            _context.AuditLogs.Add(new AuditLog
            {
                Timestamp = DateTime.UtcNow,
                Username = "admin",
                Action = $"Sisteme Yeni Doktor Tanımlandı: {request.FullName} ({request.Username})",
                IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "127.0.0.1",
                ExecutionTime = 0
            });
            await _context.SaveChangesAsync();

            return Ok(new { message = "Kullanıcı başarıyla kaydedildi!" });
        }

        [HttpPost("login")]
        public async Task<IActionResult> Login(UserLoginDto request)
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Username == request.Username);

            if (user == null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
            {
                return BadRequest(new { message = "Kullanıcı adı veya şifre hatalı." });
            }

            var token = _tokenService.GenerateToken(user);

            Console.WriteLine("----------------------------------");
            Console.WriteLine("ÜRETİLEN TOKEN: " + token);
            Console.WriteLine("----------------------------------");

            // DÜZELTİLDİ: DateTime.UtcNow yapıldı
            _context.AuditLogs.Add(new AuditLog
            {
                Timestamp = DateTime.UtcNow,
                Username = user.Username,
                Action = "Sisteme Başarılı Giriş Yapıldı",
                IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "127.0.0.1",
                ExecutionTime = 0
            });
            await _context.SaveChangesAsync();

            return Ok(new
            {
                status = "success",
                token = token,
                role = user.Role,
                username = user.Username,
                fullName = user.FullName
            });
        }

        [HttpPost("forgot-password")]
        public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest request)
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.Email);

            if (user == null)
            {
                return Ok(new { status = "success", message = "Eğer e-posta sistemde kayıtlıysa, şifre sıfırlama kodu gönderilmiştir." });
            }

            var random = new Random();
            string resetCode = random.Next(100000, 999999).ToString();

            user.ResetToken = resetCode;
            user.ResetTokenExpiry = DateTime.UtcNow.AddMinutes(15);
            await _context.SaveChangesAsync();

            await _emailService.SendPasswordResetEmailAsync(user.Email, resetCode);

            return Ok(new { status = "success", message = "Eğer e-posta sistemde kayıtlıysa, şifre sıfırlama kodu gönderilmiştir." });
        }

        [HttpPost("reset-password")]
        public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordDto request)
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == request.Email);
            if (user == null)
            {
                return BadRequest(new { message = "Geçersiz e-posta adresi." });
            }

            if (user.ResetToken != request.Token || user.ResetTokenExpiry < DateTime.UtcNow)
            {
                return BadRequest(new { message = "Girdiğiniz kod hatalı veya süresi dolmuş." });
            }

            string salt = BCrypt.Net.BCrypt.GenerateSalt(12);
            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword, salt);

            user.ResetToken = null;
            user.ResetTokenExpiry = null;

            await _context.SaveChangesAsync();

            return Ok(new { status = "success", message = "Şifreniz başarıyla güncellendi! Yeni şifrenizle giriş yapabilirsiniz." });
        }
    }
}