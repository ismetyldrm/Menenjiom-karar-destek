# classifier_model.py
import torch
import numpy as np
import os
from pathlib import Path

from monai.transforms import (
    Compose, LoadImaged, EnsureChannelFirstd,
    Orientationd, Spacingd, NormalizeIntensityd, EnsureTyped, ConcatItemsd, DeleteItemsd
)
from monai.data import Dataset, DataLoader
from monai.networks.nets import resnet50
from monai.inferers import sliding_window_inference

from brats_model import discover_input_data 

def get_classifier_transforms():
    # Colab test kodu ile aynı kanal sıralaması
    keys = ["t1n", "t1c", "t2w", "t2f"]
    return Compose([
        LoadImaged(keys=keys),
        EnsureChannelFirstd(keys=keys),
        Orientationd(keys=keys, axcodes="RAS"),
        Spacingd(keys=keys, pixdim=(1, 1, 1), mode=("bilinear", "bilinear", "bilinear", "bilinear")),
        NormalizeIntensityd(keys=keys, nonzero=True, channel_wise=True),
        ConcatItemsd(keys=keys, name="image"),
        DeleteItemsd(keys=keys),
        EnsureTyped(keys=["image"])
    ])

def predictor_wrapper(inputs, model):
    outputs = model(inputs)
    return outputs.view(outputs.shape[0], outputs.shape[1], 1, 1, 1).expand(-1, -1, 96, 96, 96).clone()

def run_classification(folder_path: str, checkpoint_path: str) -> dict:
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    
    # Model Mimarisi
    model = resnet50(spatial_dims=3, n_input_channels=4, num_classes=3).to(device)
    model.load_state_dict(torch.load(checkpoint_path, map_location=device, weights_only=False))
    model.eval()

    # Dosyaları dinamik olarak bul
    modality_paths, _, _ = discover_input_data(folder_path)
    
    # Eğer eksik modalite varsa veya tek dosya ise bu yapıyı basit tutmak için 
    # şimdilik aynı dosyayı kopyalıyoruz (brats_model ile aynı mantık)
    data_dict = {"t1c": modality_paths.get("t1c"), 
                 "t1n": modality_paths.get("t1n"), 
                 "t2f": modality_paths.get("t2f"), 
                 "t2w": modality_paths.get("t2w")}

    test_data = [data_dict]
    ds = Dataset(data=test_data, transform=get_classifier_transforms())
    loader = DataLoader(ds, batch_size=1)

    class_names = ['Meningioma', 'Glioma', 'Metastasis']

    OOD_THRESHOLD = 0.65 

    with torch.no_grad():
        for batch in loader:
            inputs = batch["image"].to(device)

            window_outputs = sliding_window_inference(
                inputs=inputs,
                roi_size=(96, 96, 96),
                sw_batch_size=2,
                predictor=lambda x: predictor_wrapper(x, model),
                overlap=0.5,
                mode="gaussian"
            )

            avg_outputs = torch.mean(window_outputs, dim=(2, 3, 4))
            probs_torch = torch.softmax(avg_outputs, dim=1)
            probs = probs_torch.cpu().numpy()[0]

            max_prob = float(np.max(probs))
            pred_idx = int(np.argmax(probs))

            # OOD kararını sadece max_prob üzerinden alıyoruz
            is_ood = bool(max_prob < OOD_THRESHOLD)
            final_class = "OOD" if is_ood else class_names[pred_idx].upper()

            # API'ye döndürülecek temiz JSON verisi
            return {
                "is_meningioma": final_class == "MENINGIOMA" and not is_ood,
                "predicted_class": final_class,
                "confidence": round(max_prob, 4),
                "is_ood": is_ood,
                "detailed_scores": {
                    class_names[0]: round(float(probs[0]), 4),
                    class_names[1]: round(float(probs[1]), 4),
                    class_names[2]: round(float(probs[2]), 4)
                }
            }