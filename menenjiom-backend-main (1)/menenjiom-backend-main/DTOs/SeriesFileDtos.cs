using System.ComponentModel.DataAnnotations;

namespace MenengiomaBackend.DTOs
{
    public class SeriesFileCreateDto
    {
        [Required]
        public int StudyID { get; set; } // En önemlisi: Bu dosyalar hangi MR çekimine ait?

        public string? AiReportContent { get; set; } // Yapay zekanın ürettiği rapor içeriği

        public string FilePath_Original { get; set; } = string.Empty; // Hastaneden gelen ham .nii dosyası

        public string FilePath_Mask { get; set; } = string.Empty; // Yapay zekanın ürettiği maske dosyası

        public float TumorVolume { get; set; } // Yapay zekanın hesapladığı hacim

        public bool IsProcessed { get; set; } // İşlem bitti mi?
    }
}