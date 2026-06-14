using MenengiomaBackend.Models;
using Microsoft.EntityFrameworkCore;

namespace MenengiomaBackend.Data
{
    public class AppDbContext : DbContext
    {
        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }
        public DbSet<AudioReport> AudioReports { get; set; }
        public DbSet<AuditLog> AuditLogs { get; set; }
        public DbSet<User> Users { get; set; }
        public DbSet<Patient> Patients { get; set; }
        public DbSet<Study> Studies { get; set; }
        public DbSet<SeriesFile> SeriesFiles { get; set; }
    }
}