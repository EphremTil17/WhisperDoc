#include "audio_device_watcher.h"

AudioDeviceWatcher* AudioDeviceWatcher::Create(HWND target) {
  auto* watcher = new AudioDeviceWatcher(target);
  HRESULT hr = ::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&watcher->enumerator_));
  if (SUCCEEDED(hr)) {
    hr = watcher->enumerator_->RegisterEndpointNotificationCallback(watcher);
  }
  if (FAILED(hr)) {
    watcher->Shutdown();
    return nullptr;
  }
  return watcher;
}

AudioDeviceWatcher::AudioDeviceWatcher(HWND target) : target_(target) {}

void AudioDeviceWatcher::Shutdown() {
  // Detach first so a callback racing with shutdown posts nowhere.
  target_.store(nullptr);
  if (enumerator_) {
    enumerator_->UnregisterEndpointNotificationCallback(this);
    enumerator_->Release();
    enumerator_ = nullptr;
  }
  Release();
}

void AudioDeviceWatcher::Acknowledge() { pending_.store(false); }

void AudioDeviceWatcher::Notify() {
  HWND target = target_.load();
  if (!target || pending_.exchange(true)) {
    return;
  }
  if (!::PostMessage(target, kAudioDevicesChangedMessage, 0, 0)) {
    pending_.store(false);
  }
}

ULONG AudioDeviceWatcher::AddRef() { return ++ref_count_; }

ULONG AudioDeviceWatcher::Release() {
  ULONG remaining = --ref_count_;
  if (remaining == 0) {
    delete this;
  }
  return remaining;
}

HRESULT AudioDeviceWatcher::QueryInterface(REFIID riid, void** object) {
  if (!object) {
    return E_POINTER;
  }
  if (riid == IID_IUnknown || riid == __uuidof(IMMNotificationClient)) {
    *object = static_cast<IMMNotificationClient*>(this);
    AddRef();
    return S_OK;
  }
  *object = nullptr;
  return E_NOINTERFACE;
}

HRESULT AudioDeviceWatcher::OnDeviceStateChanged(LPCWSTR, DWORD) {
  Notify();
  return S_OK;
}

HRESULT AudioDeviceWatcher::OnDeviceAdded(LPCWSTR) {
  Notify();
  return S_OK;
}

HRESULT AudioDeviceWatcher::OnDeviceRemoved(LPCWSTR) {
  Notify();
  return S_OK;
}

HRESULT AudioDeviceWatcher::OnDefaultDeviceChanged(EDataFlow flow, ERole role,
                                                   LPCWSTR) {
  // Fires once per role; one capture role is enough to trigger a re-check.
  if (flow == eCapture && role == eConsole) {
    Notify();
  }
  return S_OK;
}

HRESULT AudioDeviceWatcher::OnPropertyValueChanged(LPCWSTR,
                                                   const PROPERTYKEY) {
  // Property churn (names, formats) does not change device availability.
  return S_OK;
}
