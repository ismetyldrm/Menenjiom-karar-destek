using System.ComponentModel.DataAnnotations;

namespace MenengiomaBackend.Models
{
    public class Patient
    {
        [Key]
        public int PatientID { get; set; } // Diyagramdaki Primary Key (Benzersiz Kimlik)

        [Required]
        [StringLength(11)] // TC Kimlik No 11 haneli olur
        public string TCIdentityNo { get; set; } = string.Empty;

        [Required]
        public string FirstName { get; set; } = string.Empty;

        [Required]
        public string LastName { get; set; } = string.Empty;

        public DateTime BirthDate { get; set; }

        [MaxLength(1)]
        public string Gender { get; set; } = string.Empty; // E veya K (Erkek/Kadın)
    }
}