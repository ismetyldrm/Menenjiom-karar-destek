#include "flutter_window.h"

#include <optional>
#include "flutter/generated_plugin_registrant.h"

// --- SES KAYDI İÇİN EKLENEN KÜTÜPHANELER ---
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <mmsystem.h>
#pragma comment(lib, "Winmm.lib") // Windows ses sürücüsü
// ------------------------------------------

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
      
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  
  RegisterPlugins(flutter_controller_->engine());

  // ====================================================================
  // --- BİZİM CUSTOM SES KANALIMIZ (METHOD CHANNEL) BURAYA EKLENDİ ---
  // ====================================================================
  flutter::MethodChannel<> channel(
      flutter_controller_->engine()->messenger(), "com.menenjiom.app/audio",
      &flutter::StandardMethodCodec::GetInstance());

  channel.SetMethodCallHandler(
      [](const flutter::MethodCall<>& call,
         std::unique_ptr<flutter::MethodResult<>> result) {
        
        // KAYDI BAŞLAT
        if (call.method_name() == "startRecording") {
    mciSendStringA("close all", NULL, 0, NULL);
    
    // Cihazı aç
    mciSendStringA("open new type waveaudio alias myaudio", NULL, 0, NULL);
    
    // Önce ayarları yap (Sıralama çok kritiktir!)
    mciSendStringA("set myaudio bitspersample 16", NULL, 0, NULL);
    mciSendStringA("set myaudio samplespersec 44100", NULL, 0, NULL); // 44.1k standardı daha uyumludur
    mciSendStringA("set myaudio channels 1", NULL, 0, NULL);
    mciSendStringA("set myaudio alignment 2", NULL, 0, NULL); // Veri akış hizalaması
    
    // Şimdi kayda başla
    mciSendStringA("record myaudio", NULL, 0, NULL);
    
    result->Success();
}
        // KAYDI DURDUR VE KAYDET
        else if (call.method_name() == "stopRecording") {
    std::string savePath = "C:\\temp\\voice.wav"; 
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args) {
        auto it = args->find(flutter::EncodableValue("path"));
        if (it != args->end() && std::holds_alternative<std::string>(it->second)) {
            savePath = std::get<std::string>(it->second);
        }
    }

    // 1. Kaydı durdur ve Windows'un işlemi bitirmesini bekle (wait eklendi)
    mciSendStringA("stop myaudio wait", NULL, 0, NULL);
    
    // 2. Dosyayı kaydet ve yazma işlemi bitene kadar bekle (wait eklendi)
    std::string saveCmd = "save myaudio \"" + savePath + "\" wait";
    mciSendStringA(saveCmd.c_str(), NULL, 0, NULL);
    
    // 3. Cihazı kapat
    mciSendStringA("close myaudio", NULL, 0, NULL);
    
    result->Success(flutter::EncodableValue(savePath));
}
        // SESİ ÇAL (AUDIOPLAYERS ÇÖKMESİNİ ENGELLEMEK İÇİN YENİ NATIVE KOD)
        else if (call.method_name() == "playAudio") {
          std::string playPath = "";
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
              auto it = args->find(flutter::EncodableValue("path"));
              if (it != args->end() && std::holds_alternative<std::string>(it->second)) {
                  playPath = std::get<std::string>(it->second);
              }
          }
          mciSendStringA("close playaudio", NULL, 0, NULL);
          std::string openCmd = "open \"" + playPath + "\" type waveaudio alias playaudio";
          mciSendStringA(openCmd.c_str(), NULL, 0, NULL);
          mciSendStringA("play playaudio", NULL, 0, NULL);
          result->Success();
        }
        // SESİ DURDUR
        else if (call.method_name() == "stopAudio") {
          mciSendStringA("stop playaudio", NULL, 0, NULL);
          mciSendStringA("close playaudio", NULL, 0, NULL);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  // ====================================================================

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}