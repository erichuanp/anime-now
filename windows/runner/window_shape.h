#ifndef RUNNER_WINDOW_SHAPE_H_
#define RUNNER_WINDOW_SHAPE_H_

#include <windows.h>

// The app is drawn for a phone screen (1264 x 2800), so the window opens in
// that shape. Resizing is free in every direction; only the height is kept
// (in HKCU) between launches, so the window comes back phone-shaped however
// the user stretched it.
namespace window_shape {

constexpr double kDefaultRatio = 1264.0 / 2800.0;
constexpr int kDefaultHeight = 860;  // logical pixels
constexpr int kMinWidth = 320;
constexpr int kMinHeight = 560;

// Last height the user left the window at, or kDefaultHeight.
int RestoredHeight();

// Width that goes with |height| at the default ratio.
int WidthForHeight(int height);

void SaveHeight(HWND window);

// Handles WM_GETMINMAXINFO / WM_EXITSIZEMOVE / WM_CLOSE. Returns true when the
// message was fully handled.
bool HandleMessage(HWND window, UINT message, WPARAM wparam, LPARAM lparam);

}  // namespace window_shape

#endif  // RUNNER_WINDOW_SHAPE_H_
