using System.ComponentModel.DataAnnotations;

namespace MenengiomaBackend.DTOs
{
    // Yeni MR Çekimi eklerken dışarıdan isteyeceğimiz bilgiler
    public class StudyCreateDto
    {
        [Required]
        public int PatientID { get; set; } // En önemli kısım: Bu MR hangi hastanın?

        public DateTime StudyDate { get; set; } = DateTime.UtcNow; // Çekim zamanı

        [Required]
        public string Modality { get; set; } = "MR"; // Türü (MR)

        public string Status { get; set; } = "Planlandı"; // Durumu

        public string AccessionNumber { get; set; } = string.Empty; // Hastane Protokol No
    }
}