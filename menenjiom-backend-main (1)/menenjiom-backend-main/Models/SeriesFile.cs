using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace MenengiomaBackend.Models
{
    public class SeriesFile
    {
        [Key]
        public int SeriesID { get; set; }

        [Required]
        public int StudyID { get; set; }

        [ForeignKey("StudyID")]
        public Study? Study { get; set; }

        [Column(TypeName = "text")]
        public string? AiReportContent { get; set; }

        public string FilePath_Original { get; set; } = string.Empty;

        public string FilePath_Mask { get; set; } = string.Empty;

        public float TumorVolume { get; set; }

        public bool IsProcessed { get; set; } = false;
    }
}