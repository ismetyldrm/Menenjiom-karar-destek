from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
import shutil
import os
import zipfile

# 1. Model inference (analiz) fonksiyonu
from brats_model import run_inference
from classifier_model import run_classification

app = FastAPI(title="Menenjiom AI Mikroservisi")

CHECKPOINT_PATH = "./best_epoch.pth"
CLASSIFIER_CHECKPOINT = "./best_meningioma_detector.pth"
TEMP_DIR = "./temp_uploads"
OUTPUT_DIR = "./segmentation_outputs"

os.makedirs(TEMP_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)

@app.post("/api/analyze")
async def analyze_mri(file: UploadFile = File(...)):
    """C# tarafından gönderilen DICOM(ZIP) dosyasını alır, ayıklar ve analiz eder."""
    
    # Gelen dosyayı al ve geçici klasöre koy
    case_id = file.filename.split('.')[0]
    raw_folder = os.path.join(TEMP_DIR, case_id)
    
    if os.path.exists(raw_folder):
        shutil.rmtree(raw_folder)
    os.makedirs(raw_folder, exist_ok=True)
    
    file_path = os.path.join(raw_folder, file.filename)
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    # ADIM 1: Eğer gelen dosya ZIP ise (DICOM klasörü), çıkart ve zip'i sil.
    if file.filename.lower().endswith(".zip"):
        with zipfile.ZipFile(file_path, 'r') as zip_ref:
            zip_ref.extractall(raw_folder)
        os.remove(file_path) 
        
    try:
        # ADIM 2: Önce sınıflandırma çalışsın. Menengiom yoksa segmentasyon çalıştırmayacağız.
        classification = run_classification(
            folder_path=raw_folder,
            checkpoint_path=CLASSIFIER_CHECKPOINT
        )

        if not classification.get("is_meningioma", False):
            return JSONResponse(content={
                "status": "success",
                "case_name": classification.get("case_name", case_id),
                "is_meningioma": False,
                "predicted_class": classification.get("predicted_class"),
                "confidence": classification.get("confidence"),
                "is_ood": classification.get("is_ood"),
                "detailed_scores": classification.get("detailed_scores"),
                "message": "Meningiom bulgusu bulunamadı. Segmentasyon yapılmadı.",
                "mask_file_path": None,
                "volumes_cm3": None
            })

        # ADIM 3: Menengiom tespit edildiğinde segmentasyon çalıştır.
        result = run_inference(
            folder_path=raw_folder, 
            checkpoint_path=CHECKPOINT_PATH,
            output_dir=OUTPUT_DIR
        )
        
        return JSONResponse(content={
            "status": "success",
            "case_name": result["case_name"],
            "is_meningioma": True,
            "predicted_class": classification.get("predicted_class"),
            "confidence": classification.get("confidence"),
            "is_ood": classification.get("is_ood"),
            "detailed_scores": classification.get("detailed_scores"),
            "message": "Meningiom tespiti yapıldı. Segmentasyon tamamlandı.",
            "volumes_cm3": {
                "ncr": result["volumes"].get("NCR (Nekrotik Çekirdek)", {}).get("cm3", 0),
                "ed": result["volumes"].get("ED (Ödem/Edema)", {}).get("cm3", 0),
                "et": result["volumes"].get("ET (Aktif Tümör)", {}).get("cm3", 0), 
                "total_wt": result["volumes"].get("Toplam Tümör (WT)", {}).get("cm3", 0)
            },
            "mask_file_path": os.path.abspath(result["output_path"]) 
        })
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# BURASI EKLENEN KISIM
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=5000)