using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace MenengiomaBackend.Models
{
    public class AudioReport
    {
        [Key]
        public int AudioID { get; set; }

        // Hangi seriye/rapora ait olduğunu belirtmek için Foreign Key
        [Required]
        public int SeriesID { get; set; }

        [ForeignKey("SeriesID")]
        public SeriesFile? SeriesFile { get; set; }

        // Doktorun orijinal ses kaydı (PostgreSQL'de bytea olarak tutulur)
        public byte[]? DoctorVoiceData { get; set; }

        // Yapay zekanın (TTS) ürettiği ses kaydı (PostgreSQL'de bytea olarak tutulur)
        public byte[]? TtsVoiceData { get; set; }

        // Ses dosyasının formatı
        [StringLength(10)]
        public string AudioFormat { get; set; } = "m4a";

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }
}