using System;

namespace MenengiomaBackend.Models
{
    public class AuditLog
    {
        public int Id { get; set; }
        public DateTime Timestamp { get; set; } = DateTime.UtcNow; // DÜZELTİLDİ: Varsayılan olarak UTC atandı
        public string Username { get; set; }
        public string Action { get; set; }
        public string IpAddress { get; set; }
        public double ExecutionTime { get; set; }
    }
}