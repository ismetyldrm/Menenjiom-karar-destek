import os
import shutil
from pathlib import Path

import numpy as np
import nibabel as nib
import torch
import torch.nn as nn

from monai.transforms import (
    Compose, LoadImaged, EnsureChannelFirstd, EnsureTyped,
    Orientationd, Spacingd, NormalizeIntensityd,
    ConcatItemsd, DeleteItemsd,
)
from monai.networks.nets import AttentionUnet

# =============================================================================
#  MODEL YAPILANDIRMASI
# =============================================================================

CONTEXT_SLICES = 2
IN_CHANNELS = 4 * (2 * CONTEXT_SLICES + 1)  # 20
OUT_CHANNELS = 4
TARGET_SPACING = (1.0, 1.0, 1.0)
SLICE_AXIS = 2

def build_model(device: torch.device) -> nn.Module:
    return AttentionUnet(
        spatial_dims=2,
        in_channels=IN_CHANNELS,
        out_channels=OUT_CHANNELS,
        channels=(32, 64, 128, 256, 512),
        strides=(2, 2, 2, 2),
        dropout=0.2,
    ).to(device)

def get_preprocess_transform():
    keys = ["t1c", "t1n", "t2f", "t2w"]
    return Compose([
        LoadImaged(keys=keys),
        EnsureChannelFirstd(keys=keys),
        Orientationd(keys=keys, axcodes="RAS"),
        Spacingd(
            keys=keys,
            pixdim=TARGET_SPACING,
            mode=("bilinear", "bilinear", "bilinear", "bilinear"),
        ),
        NormalizeIntensityd(keys=keys, nonzero=True, channel_wise=True),
        ConcatItemsd(keys=keys, name="image"),
        DeleteItemsd(keys=keys),
        EnsureTyped(keys=["image"], dtype=torch.float32),
    ])

def get_preprocess_transform_single():
    return Compose([
        LoadImaged(keys=["image"]),
        EnsureChannelFirstd(keys=["image"]),
        Orientationd(keys=["image"], axcodes="RAS"),
        Spacingd(keys=["image"], pixdim=TARGET_SPACING, mode=("bilinear",)),
        NormalizeIntensityd(keys=["image"], nonzero=True, channel_wise=True),
        EnsureTyped(keys=["image"], dtype=torch.float32),
    ])

# =============================================================================
#  DICOM YARDIMCI FONKSİYONLARI
# =============================================================================

def _is_dicom_file(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            f.seek(128)
            if f.read(4) == b"DICM":
                return True
    except Exception:
        return False
    try:
        import pydicom
        pydicom.dcmread(path, stop_before_pixels=True, force=True)
        return True
    except Exception:
        return False

def find_dicom_series_folders(root: Path) -> list:
    root = Path(root)
    skip_names = {"segmentation_output", "_converted_nifti", "_d2n_tmp", "_tmp_d2n", "_tmp_dicom2nifti"}
    candidates = []
    
    for dirpath, dirnames, filenames in os.walk(str(root)):
        if any(s in dirpath for s in skip_names):
            dirnames[:] = []
            continue

        n_dicom = 0
        sample_checked = 0
        for fname in filenames:
            if fname.upper() == "DICOMDIR":
                continue
            ext = os.path.splitext(fname)[1].lower()
            looks_like_dicom = (ext in (".dcm", ".ima", "") or fname.split(".")[0].isdigit())
            if not looks_like_dicom:
                continue
            full = os.path.join(dirpath, fname)
            if sample_checked < 3:
                if not _is_dicom_file(full):
                    sample_checked += 1
                    continue
            sample_checked += 1
            n_dicom += 1

        if n_dicom > 0:
            candidates.append((dirpath, n_dicom))

    candidates.sort(key=lambda x: x[1], reverse=True)
    return candidates

def _convert_with_dicom2nifti(dicom_folder: str, output_path: Path, log_fn) -> Path:
    import dicom2nifti
    tmp_dir = output_path.parent / f"_d2n_tmp_{output_path.stem}"
    if tmp_dir.exists():
        shutil.rmtree(tmp_dir, ignore_errors=True)
    tmp_dir.mkdir(parents=True, exist_ok=True)

    log_fn(f"  dicom2nifti çalışıyor: {dicom_folder}")
    dicom2nifti.convert_directory(
        str(dicom_folder), str(tmp_dir),
        compression=True, reorient=True,
    )

    nii_files = list(tmp_dir.glob("*.nii.gz")) + list(tmp_dir.glob("*.nii"))
    if not nii_files:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise RuntimeError("dicom2nifti çıktı üretmedi.")

    nii_files.sort(key=lambda p: p.stat().st_size, reverse=True)
    largest = nii_files[0]

    if output_path.exists():
        output_path.unlink()
    shutil.move(str(largest), str(output_path))
    shutil.rmtree(tmp_dir, ignore_errors=True)
    return output_path

def _convert_with_sitk(dicom_folder: str, output_path: Path, log_fn) -> Path:
    import SimpleITK as sitk
    log_fn(f"  SimpleITK ile dönüştürülüyor: {dicom_folder}")

    reader = sitk.ImageSeriesReader()
    series_ids = reader.GetGDCMSeriesIDs(str(dicom_folder))

    if series_ids:
        all_series = [(sid, reader.GetGDCMSeriesFileNames(str(dicom_folder), sid))
                      for sid in series_ids]
        all_series.sort(key=lambda x: len(x[1]), reverse=True)
        chosen_files = all_series[0][1]
    else:
        candidates = sorted([str(p) for p in Path(dicom_folder).iterdir()
                             if p.is_file() and p.name.upper() != "DICOMDIR"
                             and _is_dicom_file(str(p))])
        if not candidates:
            raise RuntimeError("SimpleITK seri bulamadı, DICOM dosyası da yok.")
        chosen_files = candidates

    reader.SetFileNames(chosen_files)
    image = reader.Execute()
    sitk.WriteImage(image, str(output_path))
    return output_path

def convert_dicom_folder_to_nifti(dicom_folder: str, output_path: Path, log_fn=None) -> Path:
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    log = log_fn or (lambda m: None)

    last_err = None
    try:
        return _convert_with_dicom2nifti(dicom_folder, output_path, log)
    except Exception as e:
        last_err = e
        log(f"  ! dicom2nifti hata verdi: {e}")
        log("  SimpleITK ile yedek yöntem deneniyor...")

    try:
        return _convert_with_sitk(dicom_folder, output_path, log)
    except Exception as e:
        raise RuntimeError(
            "DICOM → NIfTI dönüşümü başarısız oldu.\n"
            f"  dicom2nifti hatası: {last_err}\n"
            f"  SimpleITK hatası : {e}\n"
        )

# =============================================================================
#  SKULL STRIPPING (Beyin Çıkarımı)
# =============================================================================

def _skull_strip_hdbet(input_path: Path, output_path: Path, mask_path: Path, log_fn) -> bool:
    try:
        try:
            from HD_BET.run import run_hd_bet
        except ImportError:
            from hd_bet.run import run_hd_bet  # type: ignore
    except ImportError:
        return False

    device_id = 0 if torch.cuda.is_available() else "cpu"
    log_fn(f"  HD-BET çalışıyor (device={device_id})...")

    try:
        run_hd_bet(
            mri_fnames=[str(input_path)],
            output_fnames=[str(output_path)],
            mode="fast",
            device=device_id,
            postprocess=True,
            do_tta=False,
            keep_mask=True,
            overwrite=True,
        )
    except TypeError:
        run_hd_bet(str(input_path), str(output_path), device=device_id)

    auto_mask = output_path.with_name(
        output_path.name.replace(".nii.gz", "").replace(".nii", "") + "_mask.nii.gz"
    )
    if auto_mask.exists() and auto_mask != mask_path:
        if mask_path.exists():
            mask_path.unlink()
        shutil.move(str(auto_mask), str(mask_path))

    return output_path.exists()

def _skull_strip_simple(input_path: Path, output_path: Path, mask_path: Path, log_fn) -> bool:
    try:
        import SimpleITK as sitk
    except ImportError:
        log_fn("  ! SimpleITK yok — skull stripping atlandı.")
        return False

    log_fn("  Basit skull stripping (SimpleITK Otsu + morfoloji)...")

    img = sitk.ReadImage(str(input_path))
    img_f = sitk.Cast(img, sitk.sitkFloat32)

    otsu = sitk.OtsuThreshold(img_f, 0, 1)
    opened = sitk.BinaryMorphologicalOpening(otsu, [2, 2, 2])
    cc = sitk.ConnectedComponent(opened)
    relabeled = sitk.RelabelComponent(cc, sortByObjectSize=True)
    largest = sitk.BinaryThreshold(relabeled, 1, 1, 1, 0)
    filled = sitk.BinaryFillhole(largest)
    eroded = sitk.BinaryErode(filled, [5, 5, 5])
    cc2 = sitk.ConnectedComponent(eroded)
    rel2 = sitk.RelabelComponent(cc2, sortByObjectSize=True)
    brain_core = sitk.BinaryThreshold(rel2, 1, 1, 1, 0)
    final_mask = sitk.BinaryDilate(brain_core, [3, 3, 3])
    final_mask = sitk.BinaryFillhole(final_mask)

    final_mask_match = sitk.Resample(
        final_mask, img, sitk.Transform(),
        sitk.sitkNearestNeighbor, 0, final_mask.GetPixelID()
    )
    masked = sitk.Mask(img, final_mask_match)

    sitk.WriteImage(masked, str(output_path))
    sitk.WriteImage(final_mask_match, str(mask_path))
    return True

def skull_strip_image(input_path: Path, output_path: Path, log_fn=None) -> tuple:
    log = log_fn or (lambda m: None)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    mask_path = output_path.parent / (
        output_path.name.replace(".nii.gz", "").replace(".nii", "") + "_brainmask.nii.gz"
    )

    log("Skull stripping başlatılıyor (önce HD-BET deneniyor)...")
    try:
        if _skull_strip_hdbet(input_path, output_path, mask_path, log):
            log(f"  ✓ HD-BET başarılı: {output_path.name}")
            return output_path, "hdbet"
    except Exception as e:
        log(f"  ! HD-BET hata verdi: {e}")
        log("  Basit yönteme geçiliyor...")

    try:
        if _skull_strip_simple(input_path, output_path, mask_path, log):
            log(f"  ✓ Basit skull stripping başarılı: {output_path.name}")
            return output_path, "simple"
    except Exception as e:
        log(f"  ! Basit skull stripping başarısız: {e}")

    log("  ! Skull stripping atlandı, orijinal görüntü kullanılacak.")
    if input_path != output_path:
        shutil.copy(str(input_path), str(output_path))
    return output_path, "skipped"

def discover_input_data(folder: str, log_fn=None) -> tuple:
    folder = Path(folder)
    log = log_fn or (lambda m: None)
    modality_keys = ["t1c", "t1n", "t2f", "t2w"]

    nii_files = sorted(list(folder.glob("*.nii.gz")) + list(folder.glob("*.nii")))
    modality_paths = {}
    case_name = None
    
    for f in nii_files:
        fname = f.name.lower()
        for mod in modality_keys:
            if (f"-{mod}." in fname or f"_{mod}." in fname
                    or fname.endswith(f"{mod}.nii.gz")
                    or fname.endswith(f"{mod}.nii")):
                modality_paths[mod] = str(f)
                if case_name is None:
                    stem = f.name
                    for suffix in [f"-{mod}.nii.gz", f"-{mod}.nii",
                                   f"_{mod}.nii.gz", f"_{mod}.nii"]:
                        if stem.lower().endswith(suffix.lower()):
                            case_name = stem[:len(stem) - len(suffix)]
                            break
                break

    if len(modality_paths) == 4:
        log("4 BraTS modalitesi tespit edildi (t1c, t1n, t2f, t2w).")
        return modality_paths, case_name or folder.name, "brats"

    if 0 < len(modality_paths) < 4:
        missing = [m for m in modality_keys if m not in modality_paths]
        first = next(iter(modality_paths.values()))
        for m in missing:
            modality_paths[m] = first
        log(f"Eksik modaliteler mevcut görüntü ile dolduruldu.")
        return modality_paths, case_name or folder.name, "partial"

    if len(nii_files) >= 1:
        nii_files_sorted = sorted(nii_files, key=lambda p: p.stat().st_size, reverse=True)
        source = nii_files_sorted[0]
        log(f"Tek NIfTI tespit edildi: {source.name}")

        out_dir = folder / "_preprocessed"
        out_dir.mkdir(exist_ok=True)
        case_name = source.name.replace(".nii.gz", "").replace(".nii", "")
        stripped = out_dir / f"{case_name}_skullstripped.nii.gz"
        stripped, method = skull_strip_image(source, stripped, log)

        return ({m: str(stripped) for m in modality_keys}, case_name, "single_nifti")

    log("NIfTI bulunamadı, DICOM serisi taranıyor...")
    candidates = find_dicom_series_folders(folder)
    if not candidates:
        raise FileNotFoundError("Klasörde geçerli NIfTI veya DICOM bulunamadı.")

    chosen, n_files = candidates[0]
    out_dir = folder / "_converted_nifti"
    out_dir.mkdir(exist_ok=True)
    case_name = folder.name
    converted = out_dir / f"{case_name}.nii.gz"
    
    convert_dicom_folder_to_nifti(chosen, converted, log)
    
    stripped = out_dir / f"{case_name}_skullstripped.nii.gz"
    stripped, method = skull_strip_image(converted, stripped, log)

    return ({m: str(stripped) for m in modality_keys}, case_name, "dicom")

def postprocess_prediction(pred: np.ndarray, min_component: int = 150) -> np.ndarray:
    from scipy.ndimage import label as scipy_label
    result = pred.copy()
    ed_mask = (pred == 2)
    if not ed_mask.any():
        return result
    labeled, n_comp = scipy_label(ed_mask)
    for comp_id in range(1, n_comp + 1):
        comp = (labeled == comp_id)
        if comp.sum() < min_component:
            result[comp] = 0
    return result

# =============================================================================
#  INFERENCE PIPELINE
# =============================================================================

def run_inference(
    folder_path: str,
    checkpoint_path: str,
    output_dir: str,
    progress_callback=None,
    log_callback=None,
) -> dict:

    def _log(msg):
        if log_callback:
            log_callback(msg)
        else:
            print(msg) # API'de konsola basması için fallback eklendi

    def _progress(val):
        if progress_callback:
            progress_callback(val)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    _log(f"Cihaz: {device}")

    folder = Path(folder_path)
    modality_paths, case_name, input_type = discover_input_data(folder_path, log_fn=_log)

    if input_type in ("single_nifti", "dicom") or len(set(modality_paths.values())) == 1:
        single_path = next(iter(modality_paths.values()))
        preprocess = get_preprocess_transform_single()
        processed = preprocess({"image": single_path})
        single_tensor = processed["image"]
        image_tensor = torch.cat([single_tensor] * 4, dim=0)
        meta_source = processed["image"]
    else:
        preprocess = get_preprocess_transform()
        data_dict = {mod: path for mod, path in modality_paths.items()}
        processed = preprocess(data_dict)
        image_tensor = processed["image"]
        meta_source = processed["image"]

    post_affine = getattr(meta_source, "meta", {}).get("affine", None) if hasattr(meta_source, "meta") else None
    if post_affine is not None:
        if hasattr(post_affine, "numpy"):
            post_affine = post_affine.numpy()
        else:
            post_affine = np.array(post_affine)
    else:
        post_affine = np.eye(4)

    C, H, W, D = image_tensor.shape
    _log(f"İşlenmiş boyut: ({H}, {W}, {D}) | {C} kanal")

    model = build_model(device)
    ckpt = torch.load(checkpoint_path, map_location=device, weights_only=False)
    model.load_state_dict(ckpt["model_state_dict"])
    model.eval()

    image_np = image_tensor.numpy()
    pred_volume = np.zeros((H, W, D), dtype=np.uint8)
    ctx = CONTEXT_SLICES
    batch_size = 32

    with torch.no_grad():
        for batch_start in range(0, D, batch_size):
            batch_end = min(batch_start + batch_size, D)
            batch_slices = []

            for s_idx in range(batch_start, batch_end):
                if ctx > 0:
                    neighbors = [
                        int(np.clip(s_idx + off, 0, D - 1))
                        for off in range(-ctx, ctx + 1)
                    ]
                    slice_input = np.concatenate(
                        [image_np[:, :, :, ns] for ns in neighbors], axis=0
                    )
                else:
                    slice_input = image_np[:, :, :, s_idx]
                batch_slices.append(slice_input)

            batch_tensor = torch.from_numpy(np.stack(batch_slices)).to(device)
            with torch.amp.autocast(device_type=device.type, enabled=(device.type == "cuda")):
                outputs = model(batch_tensor)

            preds = outputs.argmax(dim=1).cpu().numpy().astype(np.uint8)

            for i, s_idx in enumerate(range(batch_start, batch_end)):
                pred_volume[:, :, s_idx] = preds[i]

    pred_volume = postprocess_prediction(pred_volume)

    voxel_volume_mm3 = float(np.prod(TARGET_SPACING))
    volumes = {}
    label_names = {1: "NCR (Nekrotik Çekirdek)", 2: "ED (Ödem/Edema)", 3: "ET (Aktif Tümör)"}

    for label_val, label_name in label_names.items():
        n_voxels = int((pred_volume == label_val).sum())
        vol_mm3 = n_voxels * voxel_volume_mm3
        volumes[label_name] = {
            "voxels": n_voxels,
            "mm3": round(vol_mm3, 1),
            "cm3": round(vol_mm3 / 1000.0, 3),
        }

    total_voxels = int((pred_volume > 0).sum())
    total_mm3 = total_voxels * voxel_volume_mm3
    volumes["Toplam Tümör (WT)"] = {
        "voxels": total_voxels,
        "mm3": round(total_mm3, 1),
        "cm3": round(total_mm3 / 1000.0, 3),
    }

    os.makedirs(output_dir, exist_ok=True)
    out_filename = f"{case_name}_segmentation.nii.gz"
    out_path = os.path.join(output_dir, out_filename)

    nifti_img = nib.Nifti1Image(pred_volume.astype(np.uint8), affine=post_affine)
    nifti_img.header.set_zooms(TARGET_SPACING)
    nib.save(nifti_img, out_path)
    _log(f"Sonuç kaydedildi: {out_path}")

    return {
        "output_path": out_path,
        "case_name": case_name,
        "volumes": volumes,
        "shape": (H, W, D),
    }