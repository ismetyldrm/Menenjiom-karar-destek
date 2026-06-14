import requests

url = 'http://127.0.0.1:5000/api/analyze'
file_path = r'C:\BitirmeProjesiMenenjiom\test_upload.zip'
with open(file_path, 'rb') as f:
    files = {'file': (file_path.split('\\')[-1], f, 'application/zip')}
    r = requests.post(url, files=files)
    print('status_code:', r.status_code)
    print(r.text)
