#include "window_shape.h"

#include <algorithm>
#include <cmath>

namespace window_shape {

namespace {

constexpr const wchar_t kRegKey[] = L"Software\\AnimeNow";
constexpr const wchar_t kRegValue[] = L"WindowHeight";

double ScaleFor(HWND window) {
  UINT dpi = GetDpiForWindow(window);
  return dpi == 0 ? 1.0 : dpi / 96.0;
}

}  // namespace

int RestoredHeight() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  if (RegGetValueW(HKEY_CURRENT_USER, kRegKey, kRegValue, RRF_RT_REG_DWORD,
                   nullptr, &value, &size) == ERROR_SUCCESS &&
      value >= static_cast<DWORD>(kMinHeight)) {
    return static_cast<int>(value);
  }
  return kDefaultHeight;
}

int WidthForHeight(int height) {
  return std::max(kMinWidth, static_cast<int>(std::lround(height * kDefaultRatio)));
}

void SaveHeight(HWND window) {
  RECT frame{};
  if (!GetWindowRect(window, &frame)) {
    return;
  }
  const double scale = ScaleFor(window);
  DWORD height = static_cast<DWORD>(std::lround((frame.bottom - frame.top) / scale));
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegKey, 0, nullptr, 0, KEY_SET_VALUE,
                      nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  RegSetValueExW(key, kRegValue, 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&height), sizeof(height));
  RegCloseKey(key);
}

bool HandleMessage(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_GETMINMAXINFO: {
      const double scale = ScaleFor(window);
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = static_cast<LONG>(kMinWidth * scale);
      info->ptMinTrackSize.y = static_cast<LONG>(kMinHeight * scale);
      return true;
    }

    case WM_EXITSIZEMOVE:
    case WM_CLOSE:
      SaveHeight(window);
      return false;  // let the runner see it too
  }
  return false;
}

}  // namespace window_shape
