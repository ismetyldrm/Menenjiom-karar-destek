using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace MenengiomaBackend.Models
{
    public class Study
    {
        [Key]
        public int StudyID { get; set; } // Çekimin Benzersiz Numarası (Primary Key)

        [Required]
        public int PatientID { get; set; } // Hangi hastaya ait? (Foreign Key)

        // Veritabanında "Bu PatientID, Patient tablosuna aittir" demek için gereken bağ:
        [ForeignKey("PatientID")]
        public Patient? Patient { get; set; } 

        public DateTime StudyDate { get; set; } // Çekim Tarihi

        [Required]
        public string Modality { get; set; } = "MR"; // Çekim Türü (Bizde genelde MR olacak)

        public string Status { get; set; } = "Planlandı"; // Planlandı, İnceleniyor, Raporlandı vb.

        public string AccessionNumber { get; set; } = string.Empty; // Hastane Protokol/İşlem Numarası
    }
}