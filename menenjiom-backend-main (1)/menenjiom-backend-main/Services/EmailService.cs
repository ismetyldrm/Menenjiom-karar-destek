using System.Net;
using System.Net.Mail;

namespace MenengiomaBackend.Services
{
    public class EmailService
    {
        private readonly IConfiguration _config;

        public EmailService(IConfiguration config)
        {
            _config = config;
        }

        public async Task SendPasswordResetEmailAsync(string toEmail, string resetCode)
        {
            var smtpClient = new SmtpClient(_config["Smtp:Host"])
            {
                Port = int.Parse(_config["Smtp:Port"]!),
                Credentials = new NetworkCredential(_config["Smtp:Username"], _config["Smtp:Password"]),
                EnableSsl = true,
            };

            var mailMessage = new MailMessage
            {
                From = new MailAddress("noreply@menenjiom.com", "Menenjiom AI Asistanı"),
                Subject = "Şifre Sıfırlama Kodunuz",
                Body = $"Merhaba Değerli Doktorumuz,\n\nSisteme giriş şifrenizi sıfırlamak için tek kullanımlık onay kodunuz aşağıdadır:\n\nKOD: {resetCode}\n\nBu kod güvenliğiniz için 15 dakika boyunca geçerlidir.\nİyi çalışmalar dileriz.",
                IsBodyHtml = false,
            };
            mailMessage.To.Add(toEmail);

            await smtpClient.SendMailAsync(mailMessage);
        }
    }
}