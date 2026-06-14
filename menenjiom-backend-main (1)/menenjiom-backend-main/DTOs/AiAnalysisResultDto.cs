namespace MenengiomaBackend.DTOs
{
    public class AiAnalysisResultDto
    {
        public string? Status { get; set; }
        public string? Case_name { get; set; }
        public VolumesCm3? Volumes_cm3 { get; set; }
        public string? Mask_file_path { get; set; }
    public bool? Is_meningioma { get; set; }
    public string? Predicted_class { get; set; }
    public double? Confidence { get; set; }
    public bool? Is_ood { get; set; }
    public string? Message { get; set; }
    }

    public class VolumesCm3
    {
        public double Ncr { get; set; } // Ncr (Necrotic Tumor Core - Nekrotik Çekirdek)
        public double Ed { get; set; }  // Ed (Peritumoral Edema - Ödem)
        public double Et { get; set; }  // Et (Enhancing Tumor - Aktif Tümör)
        public double Total_wt { get; set; } //Total_wt (Whole Tumor - Toplam Tümör Hacmi)
    }
}