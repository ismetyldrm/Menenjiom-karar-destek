using System.ComponentModel.DataAnnotations;

namespace MenengiomaBackend.DTOs
{
    // Yeni hasta eklerken Flutter'dan isteyeceğimiz bilgiler
    public class PatientCreateDto
    {
        [Required]
        [StringLength(11)]
        public string TCIdentityNo { get; set; } = string.Empty;

        [Required]
        public string FirstName { get; set; } = string.Empty;

        [Required]
        public string LastName { get; set; } = string.Empty;

        public DateTime BirthDate { get; set; }

        [MaxLength(1)]
        public string Gender { get; set; } = string.Empty; // Sadece "E" veya "K"
    }
}