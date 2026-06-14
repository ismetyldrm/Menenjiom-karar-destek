using System.ComponentModel.DataAnnotations;

namespace MenengiomaBackend.DTOs
{
    public class AudioReportCreateDto
    {
        [Required(ErrorMessage = "SeriesID zorunludur.")]
        public int SeriesID { get; set; }

        [Required(ErrorMessage = "Ses verisi (Base64) boş olamaz.")]
        public string DoctorVoiceData { get; set; } = string.Empty;

        // Formatı zorunlu tutmuyoruz, eğer gelmezse Controller'da "m4a" atayacağız
        public string? AudioFormat { get; set; }
    }
}