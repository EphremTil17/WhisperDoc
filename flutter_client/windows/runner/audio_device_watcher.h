#ifndef RUNNER_AUDIO_DEVICE_WATCHER_H_
#define RUNNER_AUDIO_DEVICE_WATCHER_H_

#include <windows.h>
#include <mmdeviceapi.h>

#include <atomic>

// Posted to the owner window when the set of audio endpoints may have changed.
// At most one is in flight until the owner calls Acknowledge(), so a burst of
// OS notifications (one device arrival fires several) costs a single message.
constexpr UINT kAudioDevicesChangedMessage = WM_APP + 0x41;

// Receives Windows Core Audio endpoint notifications (device added, removed,
// enabled/disabled, default capture device changed) and forwards them to a
// window on the UI thread. Event-driven: the OS pushes changes, so nothing
// runs while devices are stable.
//
// Callbacks arrive on Core Audio worker threads and must not block, so they
// only post a window message; all Flutter interaction happens on the UI thread.
class AudioDeviceWatcher : public IMMNotificationClient {
 public:
  // Registers a watcher that notifies |target|, or returns nullptr when Core
  // Audio is unavailable. The caller owns the result and must call Shutdown().
  static AudioDeviceWatcher* Create(HWND target);

  // Unregisters from Core Audio and releases the creator's reference.
  void Shutdown();

  // Re-arms posting once the owner window has handled a notification.
  void Acknowledge();

  // IUnknown
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** object) override;

  // IMMNotificationClient
  HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(LPCWSTR device_id,
                                                 DWORD new_state) override;
  HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR device_id) override;
  HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR device_id) override;
  HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(
      EDataFlow flow, ERole role, LPCWSTR default_device_id) override;
  HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(
      LPCWSTR device_id, const PROPERTYKEY key) override;

 private:
  explicit AudioDeviceWatcher(HWND target);
  ~AudioDeviceWatcher() = default;  // Destroyed only through Release().

  void Notify();

  std::atomic<HWND> target_;
  IMMDeviceEnumerator* enumerator_ = nullptr;
  std::atomic<ULONG> ref_count_{1};
  std::atomic<bool> pending_{false};
};

#endif  // RUNNER_AUDIO_DEVICE_WATCHER_H_
