from flask import Flask, send_file, request, jsonify
from werkzeug.utils import secure_filename
import nibabel as nib
import numpy as np
from PIL import Image
import io
import os
import zipfile
import tempfile

app = Flask(__name__)

UPLOAD_DIR = os.path.join(tempfile.gettempdir(), "menengiom_temp_mri")
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
    response.headers['Access-Control-Allow-Methods'] = 'GET,POST,OPTIONS'
    return response

# Önbellek (Cache) mekanizması
CACHE = {
    "zip_path": None,
    "mask_path": None,
    "mri_data": None,
    "mask_data": None
}

def load_data(zip_path, mask_path):
    global CACHE
    # Yeni bir hasta seçildiyse verileri RAM'e yükle
    if zip_path != CACHE["zip_path"]:
        CACHE["mri_data"] = load_nifti_from_zip(zip_path)
        CACHE["zip_path"] = zip_path
    
    if mask_path and mask_path != CACHE["mask_path"]:
        if os.path.isabs(mask_path):
            mask_file_path = mask_path
        else:
            mask_file_path = os.path.join(UPLOAD_DIR, secure_filename(mask_path))

        if os.path.exists(mask_file_path):
            nii_mask = nib.load(mask_file_path)
            nii_mask = nib.as_closest_canonical(nii_mask)
            CACHE["mask_data"] = nii_mask.get_fdata()
            CACHE["mask_path"] = mask_file_path
        else:
            CACHE["mask_data"] = None

@app.route('/api/upload_zip', methods=['POST'])
def upload_zip():
    if 'zip_file' not in request.files:
        return jsonify({"error": "No zip_file part"}), 400

    zip_file = request.files['zip_file']
    if zip_file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    filename = secure_filename(zip_file.filename)
    dest_path = os.path.join(UPLOAD_DIR, filename)
    zip_file.save(dest_path)

    return jsonify({"status": "success", "zip_path": filename}), 200

@app.route('/api/get_slice/<int:slice_idx>')
def get_slice(slice_idx):
    zip_path = request.args.get('zip_path')
    mask_path = request.args.get('mask_path')
    show_mask = request.args.get('show_mask', 'false').lower() == 'true'
    plane = request.args.get('plane', 'axial').lower()

    try:
        if not zip_path:
            return serve_empty(20)

        if not os.path.isabs(zip_path):
            zip_path = os.path.join(UPLOAD_DIR, secure_filename(zip_path))

        load_data(zip_path, mask_path)
        
        if CACHE["mri_data"] is None:
            return serve_empty(40)

        # 3D Görüntü matris boyutlarını dinamik alıyoruz (X: Sagittal, Y: Coronal, Z: Axial)
        dim_x, dim_y, dim_z = CACHE["mri_data"].shape

        # ---------------------------------------------------------
        # MULTI-PLANAR RECONSTRUCTION (MPR) DİLİMLEME
        # ---------------------------------------------------------
        if plane == "sagittal":
            # Yandan Görünüm (X Ekseni Kesiti)
            idx = max(0, min(slice_idx, dim_x - 1))
            mri_slice = np.rot90(CACHE["mri_data"][idx, :, :], 1)
            if show_mask and CACHE["mask_data"] is not None:
                mask_slice = np.rot90(CACHE["mask_data"][idx, :, :], 1)

        elif plane == "coronal":
            # Önden Görünüm (Y Ekseni Kesiti)
            idx = max(0, min(slice_idx, dim_y - 1))
            mri_slice = np.rot90(CACHE["mri_data"][:, idx, :], 1)
            if show_mask and CACHE["mask_data"] is not None:
                mask_slice = np.rot90(CACHE["mask_data"][:, idx, :], 1)

        else:
            # Axial - Üstten Görünüm (Z Ekseni Kesiti)
            idx = max(0, min(slice_idx, dim_z - 1))
            mri_slice = np.rot90(CACHE["mri_data"][:, :, idx], 1)
            mri_slice = np.fliplr(mri_slice) # Ayna efektini düzelt
            if show_mask and CACHE["mask_data"] is not None:
                mask_slice = np.rot90(CACHE["mask_data"][:, :, idx], 1)
                mask_slice = np.fliplr(mask_slice)

        # Görüntüyü normalize et ve RGBA formatına çevir
        mri_norm = normalize_image(mri_slice)
        mri_img = Image.fromarray(mri_norm).convert('RGBA')

        # ---------------------------------------------------------
        # MASKE KATMANI BİNDİRME
        # ---------------------------------------------------------
        if show_mask and CACHE["mask_data"] is not None:
            # Şeffaf bir renk paleti oluştur
            color_mask = np.zeros((mask_slice.shape[0], mask_slice.shape[1], 4), dtype=np.uint8)
            
            # BraTS Etiketleri ve Renkleri:
            color_mask[mask_slice == 1] = [255, 50, 50, 160]  # 1: NCR (Nekrotik Çekirdek) -> Kırmızı
            color_mask[mask_slice == 2] = [255, 255, 50, 80]  # 2: ED (Ödem) -> Sarı
            color_mask[mask_slice == 3] = [50, 200, 255, 180] # 3: ET (Aktif Tümör) -> Turkuaz/Açık Mavi
            
            # Maskeyi görüntüye dönüştür ve orijinal MR'ın üstüne bindir
            mask_img = Image.fromarray(color_mask)
            mri_img = Image.alpha_composite(mri_img, mask_img)

        return serve_pil_image(mri_img.convert('RGB'))

    except Exception as e:
        print(f"Hata: {e}")
        return serve_empty(50)

def normalize_image(data):
    ptp = np.ptp(data)
    if ptp == 0: ptp = 1
    return (255 * (data - np.min(data)) / ptp).astype(np.uint8)

def serve_empty(color):
    return serve_pil_image(Image.new('RGB', (240, 240), color=(color, color, color)))

def serve_pil_image(img):
    img_io = io.BytesIO()
    img.save(img_io, 'PNG')
    img_io.seek(0)
    return send_file(img_io, mimetype='image/png')

def load_nifti_from_zip(zip_path):
    try:
        extract_path = os.path.join(UPLOAD_DIR, "extracted")
        os.makedirs(extract_path, exist_ok=True)
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            nifti_files = [f for f in zip_ref.namelist() if f.endswith('.nii.gz')]
            target = next((f for f in nifti_files if 't1c' in f.lower()), nifti_files[0])
            zip_ref.extract(target, extract_path)
            
            # Orijinal MR'ı anatomik standarda (Canonical) hizala
            nii = nib.load(os.path.join(extract_path, target))
            nii = nib.as_closest_canonical(nii)
            return nii.get_fdata()
    except Exception as e: 
        print(f"Zip Yükleme Hatası: {e}")
        return None

if __name__ == '__main__':
    print("DİNAMİK MR Kesici Sunucusu Başlatıldı! Port: 5001")
    app.run(host='127.0.0.1', port=5001)