import torch
from classifier_model import run_classification

result = run_classification('preprocessed_mri\\BraTS-MEN-00058-000', 'best_meningioma_detector.pth')
print(result)
