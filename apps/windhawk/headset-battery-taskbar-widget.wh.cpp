// ==WindhawkMod==
// @id headset-battery-taskbar-widget
// @name Headset Battery Taskbar Widget
// @description Shows a Bluetooth headset battery widget on the Windows 11 taskbar.
// @version 0.1.0
// @author Rodolfo Camara
// @include explorer.exe
// @compilerOptions -lgdi32 -luser32 -lsetupapi -lwinmm -lole32
// ==/WindhawkMod==

// ==WindhawkModReadme==
/*
# Headset Battery Taskbar Widget

Shows the aggregate Bluetooth headset battery percentage exposed by Windows in
the empty area of a vertical Windows 11 taskbar.

The battery is read from the Windows PnP property used by Bluetooth headset
Hands-Free devices:

`{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2`

For Soundcore TWS earbuds, this is the same aggregate percentage shown by the
Windows Bluetooth settings page. Left/right/case values are not exposed by this
property and require decoding Soundcore's proprietary BLE protocol.
*/
// ==/WindhawkModReadme==

// ==WindhawkModSettings==
/*
- DeviceNamePattern: soundcore Liberty 4 Pro
  $name: Device name contains
- PollSeconds: 30
  $name: Poll interval, seconds
- LowBatteryPercent: 30
  $name: Low battery threshold
- AlertSound: true
  $name: Play sound when battery becomes low
- WidgetWidth: 44
  $name: Widget width
- WidgetHeight: 64
  $name: Widget height
- OffsetX: 4
  $name: Horizontal offset
- OffsetY: 10
  $name: Vertical offset
- DarkBackground: true
  $name: Use dark background
- PrimaryOutputNamePattern: soundcore Liberty 4 Pro
  $name: Primary audio output contains
- SecondaryOutputNamePattern: LG
  $name: Secondary audio output contains
- DetailedBatteryFile: "%LOCALAPPDATA%\\SoundcoreBattery\\state.txt"
  $name: Detailed battery state file
- HostInTaskbar: true
  $name: Host window inside taskbar
*/
// ==/WindhawkModSettings==

#include <windows.h>
#include <mmdeviceapi.h>
#include <propidl.h>
#include <setupapi.h>
#include <devpropdef.h>
#include <mmsystem.h>
#include <strsafe.h>

#include <algorithm>
#include <cwctype>
#include <string>

struct Settings {
    std::wstring deviceNamePattern;
    int pollSeconds = 30;
    int lowBatteryPercent = 30;
    bool alertSound = true;
    int widgetWidth = 44;
    int widgetHeight = 34;
    int offsetX = 4;
    int offsetY = 10;
    bool darkBackground = true;
    std::wstring primaryOutputNamePattern;
    std::wstring secondaryOutputNamePattern;
    std::wstring detailedBatteryFile;
    bool hostInTaskbar = true;
};

struct DetailedBattery {
    int left = -1;
    int right = -1;
    int batteryCase = -1;
    bool leftCharging = false;
    bool rightCharging = false;
    bool caseCharging = false;
    DWORD lastTick = 0;
};

static Settings g_settings;
static HWND g_widgetWindow = nullptr;
static HANDLE g_thread = nullptr;
static HANDLE g_pipeThread = nullptr;
static HANDLE g_pipeHandle = INVALID_HANDLE_VALUE;
static DWORD g_threadId = 0;
static DWORD g_pipeThreadId = 0;
static volatile bool g_running = true;
static int g_batteryPercent = -1;
static bool g_wasLowBattery = false;
static int g_audioOutputState = 0; // 0 unknown, 1 primary/headset, 2 secondary/monitor.
static DetailedBattery g_detailedBattery;
static bool g_hostedInTaskbar = false;

static constexpr UINT_PTR TIMER_POLL = 1;
static constexpr UINT_PTR TIMER_REPOSITION = 2;
static constexpr UINT MENU_TEST_SOUND = 1001;
static constexpr UINT MENU_TOGGLE_OUTPUT = 1002;
static constexpr wchar_t WIDGET_CLASS_NAME[] = L"WindhawkHeadsetBatteryWidget";
static constexpr wchar_t PIPE_NAME[] = LR"(\\.\pipe\SoundcoreBatteryWidget)";

static const PROPERTYKEY PKEY_Device_FriendlyName_Local = {
    {0xA45C254E, 0xDF1C, 0x4EFD, {0x80, 0x20, 0x67, 0xD1, 0x46, 0xA8, 0x50, 0xE0}},
    14
};

static const CLSID CLSID_PolicyConfigClient = {
    0x870af99c, 0x171d, 0x4f9e, {0xaf, 0x0d, 0xe6, 0x3d, 0xf4, 0x0c, 0x2b, 0xc9}
};

static const IID IID_IPolicyConfig = {
    0xf8679f50, 0x850a, 0x41cf, {0x9c, 0x72, 0x43, 0x0f, 0x29, 0x02, 0x90, 0xc8}
};

struct IPolicyConfig : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE GetMixFormat(PCWSTR, WAVEFORMATEX**) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetDeviceFormat(PCWSTR, INT, WAVEFORMATEX**) = 0;
    virtual HRESULT STDMETHODCALLTYPE ResetDeviceFormat(PCWSTR) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetDeviceFormat(PCWSTR, WAVEFORMATEX*, WAVEFORMATEX*) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetProcessingPeriod(PCWSTR, INT, PINT64, PINT64) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetProcessingPeriod(PCWSTR, PINT64) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetShareMode(PCWSTR, void*) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetShareMode(PCWSTR, void*) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetPropertyValue(PCWSTR, const PROPERTYKEY&, PROPVARIANT*) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetPropertyValue(PCWSTR, const PROPERTYKEY&, PROPVARIANT*) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetDefaultEndpoint(PCWSTR, ERole) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetEndpointVisibility(PCWSTR, INT) = 0;
};

// Observed Bluetooth headset battery property:
// {104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2
static const DEVPROPKEY PKEY_BluetoothHeadsetBattery = {
    {0x104EA319, 0x6EE2, 0x4701, {0xBD, 0x47, 0x8D, 0xDB, 0xF4, 0x25, 0xBB, 0xE5}},
    2
};

static std::wstring ToLower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t c) {
        return static_cast<wchar_t>(towlower(c));
    });
    return value;
}

static bool ContainsInsensitive(const std::wstring& value, const std::wstring& pattern) {
    if (pattern.empty()) {
        return true;
    }

    return ToLower(value).find(ToLower(pattern)) != std::wstring::npos;
}

static std::wstring ExpandEnvironment(const std::wstring& value) {
    WCHAR buffer[MAX_PATH] = {};
    DWORD size = ExpandEnvironmentStringsW(value.c_str(), buffer, ARRAYSIZE(buffer));
    if (size == 0 || size > ARRAYSIZE(buffer)) {
        return value;
    }

    return buffer;
}

class ScopedCoInit {
public:
    ScopedCoInit() {
        hr_ = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    }

    ~ScopedCoInit() {
        if (SUCCEEDED(hr_)) {
            CoUninitialize();
        }
    }

    bool ok() const {
        return SUCCEEDED(hr_) || hr_ == RPC_E_CHANGED_MODE;
    }

private:
    HRESULT hr_ = E_FAIL;
};

static bool GetDeviceFriendlyName(
    HDEVINFO devices,
    SP_DEVINFO_DATA& info,
    std::wstring* value) {

    WCHAR buffer[512] = {};
    DWORD requiredSize = 0;

    if (!SetupDiGetDeviceRegistryPropertyW(
            devices,
            &info,
            SPDRP_FRIENDLYNAME,
            nullptr,
            reinterpret_cast<PBYTE>(buffer),
            sizeof(buffer),
            &requiredSize)) {
        return false;
    }

    *value = buffer;
    return true;
}

static bool GetDeviceByteProperty(
    HDEVINFO devices,
    SP_DEVINFO_DATA& info,
    const DEVPROPKEY& key,
    BYTE* value) {

    DEVPROPTYPE type = 0;
    BYTE buffer = 0;
    DWORD requiredSize = 0;

    if (!SetupDiGetDevicePropertyW(
            devices,
            &info,
            &key,
            &type,
            &buffer,
            sizeof(buffer),
            &requiredSize,
            0)) {
        return false;
    }

    if (type != DEVPROP_TYPE_BYTE) {
        return false;
    }

    *value = buffer;
    return true;
}

static int QueryHeadsetBatteryPercent() {
    HDEVINFO devices = SetupDiGetClassDevsW(
        nullptr,
        nullptr,
        nullptr,
        DIGCF_ALLCLASSES | DIGCF_PRESENT);

    if (devices == INVALID_HANDLE_VALUE) {
        return -1;
    }

    int bestValue = -1;

    for (DWORD index = 0;; index++) {
        SP_DEVINFO_DATA info = {};
        info.cbSize = sizeof(info);

        if (!SetupDiEnumDeviceInfo(devices, index, &info)) {
            break;
        }

        BYTE battery = 0;
        if (!GetDeviceByteProperty(devices, info, PKEY_BluetoothHeadsetBattery, &battery)) {
            continue;
        }

        std::wstring friendlyName;
        GetDeviceFriendlyName(devices, info, &friendlyName);

        if (!ContainsInsensitive(friendlyName, g_settings.deviceNamePattern)) {
            continue;
        }

        if (battery <= 100) {
            bestValue = static_cast<int>(battery);
            break;
        }
    }

    SetupDiDestroyDeviceInfoList(devices);
    return bestValue;
}

static void UpdateBattery(HWND hwnd) {
    int newValue = QueryHeadsetBatteryPercent();
    if (newValue == g_batteryPercent) {
        return;
    }

    g_batteryPercent = newValue;

    bool isLow = g_batteryPercent >= 0 && g_batteryPercent <= g_settings.lowBatteryPercent;
    if (isLow && !g_wasLowBattery && g_settings.alertSound) {
        PlaySoundW(L"SystemExclamation", nullptr, SND_ALIAS | SND_ASYNC);
    }

    g_wasLowBattery = isLow;
    InvalidateRect(hwnd, nullptr, TRUE);
}

static bool ParseIntAfterToken(const std::wstring& text, const wchar_t* token, int* value) {
    size_t pos = text.find(token);
    if (pos == std::wstring::npos) {
        return false;
    }

    pos += wcslen(token);
    int parsed = _wtoi(text.c_str() + pos);
    if (parsed < 0 || parsed > 100) {
        return false;
    }

    *value = parsed;
    return true;
}

static bool ParseBoolAfterToken(const std::wstring& text, const wchar_t* token, bool* value) {
    size_t pos = text.find(token);
    if (pos == std::wstring::npos) {
        return false;
    }

    pos += wcslen(token);
    *value = text.compare(pos, 1, L"1") == 0 ||
             text.compare(pos, 4, L"true") == 0 ||
             text.compare(pos, 4, L"True") == 0;
    return true;
}

static bool ReadDetailedBatteryFile(DetailedBattery* battery) {
    if (g_settings.detailedBatteryFile.empty()) {
        return false;
    }

    std::wstring path = ExpandEnvironment(g_settings.detailedBatteryFile);
    HANDLE file = CreateFileW(
        path.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);

    if (file == INVALID_HANDLE_VALUE) {
        return false;
    }

    char buffer[512] = {};
    DWORD bytesRead = 0;
    BOOL ok = ReadFile(file, buffer, sizeof(buffer) - 1, &bytesRead, nullptr);
    CloseHandle(file);

    if (!ok || bytesRead == 0) {
        return false;
    }

    int wideLen = MultiByteToWideChar(CP_UTF8, 0, buffer, bytesRead, nullptr, 0);
    if (wideLen <= 0) {
        return false;
    }

    std::wstring text(wideLen, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, buffer, bytesRead, text.data(), wideLen);

    DetailedBattery parsed = {};
    bool hasLeft = ParseIntAfterToken(text, L"L=", &parsed.left);
    bool hasRight = ParseIntAfterToken(text, L"R=", &parsed.right);
    bool hasCase = ParseIntAfterToken(text, L"C=", &parsed.batteryCase);
    bool hasAny = hasLeft || hasRight || hasCase;

    if (!hasAny) {
        return false;
    }

    ParseBoolAfterToken(text, L"LC=", &parsed.leftCharging);
    ParseBoolAfterToken(text, L"RC=", &parsed.rightCharging);
    ParseBoolAfterToken(text, L"CC=", &parsed.caseCharging);
    parsed.lastTick = GetTickCount();
    *battery = parsed;
    return true;
}

static bool ParseDetailedBatteryText(const std::wstring& text, DetailedBattery* battery) {
    DetailedBattery parsed = {};
    bool hasLeft = ParseIntAfterToken(text, L"L=", &parsed.left);
    bool hasRight = ParseIntAfterToken(text, L"R=", &parsed.right);
    bool hasCase = ParseIntAfterToken(text, L"C=", &parsed.batteryCase);
    bool hasAny = hasLeft || hasRight || hasCase;

    if (!hasAny) {
        return false;
    }

    ParseBoolAfterToken(text, L"LC=", &parsed.leftCharging);
    ParseBoolAfterToken(text, L"RC=", &parsed.rightCharging);
    ParseBoolAfterToken(text, L"CC=", &parsed.caseCharging);
    parsed.lastTick = GetTickCount();
    *battery = parsed;
    return true;
}

static bool ParseDetailedBatteryUtf8(const char* text, DWORD textLength, DetailedBattery* battery) {
    int wideLen = MultiByteToWideChar(CP_UTF8, 0, text, textLength, nullptr, 0);
    if (wideLen <= 0) {
        return false;
    }

    std::wstring wide(wideLen, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text, textLength, wide.data(), wideLen);
    return ParseDetailedBatteryText(wide, battery);
}

static bool DetailedBatteryEquals(const DetailedBattery& a, const DetailedBattery& b) {
    return a.left == b.left &&
           a.right == b.right &&
           a.batteryCase == b.batteryCase &&
           a.leftCharging == b.leftCharging &&
           a.rightCharging == b.rightCharging &&
           a.caseCharging == b.caseCharging;
}

static void UpdateDetailedBattery(HWND hwnd) {
    DetailedBattery newBattery;
    if (!ReadDetailedBatteryFile(&newBattery)) {
        return;
    }

    if (DetailedBatteryEquals(newBattery, g_detailedBattery)) {
        return;
    }

    g_detailedBattery = newBattery;
    InvalidateRect(hwnd, nullptr, TRUE);
}

static void ApplyDetailedBattery(HWND hwnd, const DetailedBattery& newBattery) {
    if (DetailedBatteryEquals(newBattery, g_detailedBattery)) {
        return;
    }

    g_detailedBattery = newBattery;
    if (hwnd) {
        InvalidateRect(hwnd, nullptr, TRUE);
    }
}

static DWORD WINAPI PipeThreadProc(LPVOID) {
    while (g_running) {
        HANDLE pipe = CreateFileW(
            PIPE_NAME,
            GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            nullptr,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);

        if (pipe == INVALID_HANDLE_VALUE) {
            Sleep(1000);
            continue;
        }

        g_pipeHandle = pipe;

        DWORD mode = PIPE_READMODE_MESSAGE | PIPE_NOWAIT;
        SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr);

        while (g_running) {
            char buffer[256] = {};
            DWORD bytesRead = 0;
            if (!ReadFile(pipe, buffer, sizeof(buffer) - 1, &bytesRead, nullptr)) {
                DWORD error = GetLastError();
                if (error == ERROR_NO_DATA) {
                    Sleep(100);
                    continue;
                }

                break;
            }

            if (bytesRead == 0) {
                Sleep(100);
                continue;
            }

            DetailedBattery parsed;
            if (ParseDetailedBatteryUtf8(buffer, bytesRead, &parsed)) {
                ApplyDetailedBattery(g_widgetWindow, parsed);
            }
        }

        CloseHandle(pipe);
        g_pipeHandle = INVALID_HANDLE_VALUE;
        Sleep(500);
    }

    return 0;
}

static bool GetAudioDeviceName(IMMDevice* device, std::wstring* name) {
    IPropertyStore* store = nullptr;
    HRESULT hr = device->OpenPropertyStore(STGM_READ, &store);
    if (FAILED(hr)) {
        return false;
    }

    PROPVARIANT value;
    PropVariantInit(&value);
    hr = store->GetValue(PKEY_Device_FriendlyName_Local, &value);

    bool ok = false;
    if (SUCCEEDED(hr) && value.vt == VT_LPWSTR && value.pwszVal) {
        *name = value.pwszVal;
        ok = true;
    }

    PropVariantClear(&value);
    store->Release();
    return ok;
}

static bool GetAudioDeviceId(IMMDevice* device, std::wstring* id) {
    LPWSTR rawId = nullptr;
    HRESULT hr = device->GetId(&rawId);
    if (FAILED(hr) || !rawId) {
        return false;
    }

    *id = rawId;
    CoTaskMemFree(rawId);
    return true;
}

static bool SetDefaultAudioOutput(const std::wstring& deviceId) {
    IPolicyConfig* policyConfig = nullptr;
    HRESULT hr = CoCreateInstance(
        CLSID_PolicyConfigClient,
        nullptr,
        CLSCTX_ALL,
        IID_IPolicyConfig,
        reinterpret_cast<void**>(&policyConfig));

    if (FAILED(hr) || !policyConfig) {
        return false;
    }

    bool ok = true;
    ok = SUCCEEDED(policyConfig->SetDefaultEndpoint(deviceId.c_str(), eConsole)) && ok;
    ok = SUCCEEDED(policyConfig->SetDefaultEndpoint(deviceId.c_str(), eMultimedia)) && ok;
    ok = SUCCEEDED(policyConfig->SetDefaultEndpoint(deviceId.c_str(), eCommunications)) && ok;

    policyConfig->Release();
    return ok;
}

static int QueryDefaultAudioOutputState() {
    if (g_settings.primaryOutputNamePattern.empty() &&
        g_settings.secondaryOutputNamePattern.empty()) {
        return 0;
    }

    ScopedCoInit coInit;
    if (!coInit.ok()) {
        return 0;
    }

    IMMDeviceEnumerator* enumerator = nullptr;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void**>(&enumerator));

    if (FAILED(hr) || !enumerator) {
        return 0;
    }

    int state = 0;
    IMMDevice* defaultDevice = nullptr;
    if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &defaultDevice)) &&
        defaultDevice) {
        std::wstring defaultName;
        if (GetAudioDeviceName(defaultDevice, &defaultName)) {
            if (!g_settings.primaryOutputNamePattern.empty() &&
                ContainsInsensitive(defaultName, g_settings.primaryOutputNamePattern)) {
                state = 1;
            } else if (!g_settings.secondaryOutputNamePattern.empty() &&
                       ContainsInsensitive(defaultName, g_settings.secondaryOutputNamePattern)) {
                state = 2;
            }
        }

        defaultDevice->Release();
    }

    enumerator->Release();
    return state;
}

static void UpdateAudioOutputState(HWND hwnd) {
    int newState = QueryDefaultAudioOutputState();
    if (newState == g_audioOutputState) {
        return;
    }

    g_audioOutputState = newState;
    InvalidateRect(hwnd, nullptr, TRUE);
}

static bool ToggleAudioOutput() {
    if (g_settings.primaryOutputNamePattern.empty() ||
        g_settings.secondaryOutputNamePattern.empty()) {
        return false;
    }

    ScopedCoInit coInit;
    if (!coInit.ok()) {
        return false;
    }

    IMMDeviceEnumerator* enumerator = nullptr;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void**>(&enumerator));

    if (FAILED(hr) || !enumerator) {
        return false;
    }

    std::wstring defaultName;
    IMMDevice* defaultDevice = nullptr;
    if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &defaultDevice)) &&
        defaultDevice) {
        GetAudioDeviceName(defaultDevice, &defaultName);
        defaultDevice->Release();
    }

    IMMDeviceCollection* devices = nullptr;
    hr = enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &devices);
    if (FAILED(hr) || !devices) {
        enumerator->Release();
        return false;
    }

    std::wstring primaryId;
    std::wstring secondaryId;

    UINT count = 0;
    devices->GetCount(&count);
    for (UINT i = 0; i < count; i++) {
        IMMDevice* device = nullptr;
        if (FAILED(devices->Item(i, &device)) || !device) {
            continue;
        }

        std::wstring name;
        std::wstring id;
        if (GetAudioDeviceName(device, &name) && GetAudioDeviceId(device, &id)) {
            if (primaryId.empty() && ContainsInsensitive(name, g_settings.primaryOutputNamePattern)) {
                primaryId = id;
            }
            if (secondaryId.empty() && ContainsInsensitive(name, g_settings.secondaryOutputNamePattern)) {
                secondaryId = id;
            }
        }

        device->Release();
    }

    devices->Release();
    enumerator->Release();

    if (primaryId.empty() || secondaryId.empty()) {
        return false;
    }

    const bool currentIsPrimary =
        ContainsInsensitive(defaultName, g_settings.primaryOutputNamePattern);
    const std::wstring& targetId = currentIsPrimary ? secondaryId : primaryId;

    bool ok = SetDefaultAudioOutput(targetId);
    PlaySoundW(ok ? L"SystemAsterisk" : L"SystemHand", nullptr, SND_ALIAS | SND_ASYNC);
    if (ok && g_widgetWindow) {
        UpdateAudioOutputState(g_widgetWindow);
    }
    return ok;
}

static void ShowActionMenu(HWND hwnd) {
    HMENU menu = CreatePopupMenu();
    if (!menu) {
        return;
    }

    AppendMenuW(menu, MF_STRING, MENU_TEST_SOUND, L"Testar som");
    AppendMenuW(menu, MF_STRING, MENU_TOGGLE_OUTPUT, L"Alternar saida de audio");

    POINT point = {};
    GetCursorPos(&point);
    SetForegroundWindow(hwnd);
    TrackPopupMenu(menu, TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd, nullptr);
    DestroyMenu(menu);
}

static RECT GetTaskbarRect() {
    RECT rect = {};
    HWND taskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (taskbar) {
        GetWindowRect(taskbar, &rect);
    }
    return rect;
}

static HWND GetTaskbarWindow() {
    return FindWindowW(L"Shell_TrayWnd", nullptr);
}

static void RepositionWidget(HWND hwnd) {
    RECT taskbar = GetTaskbarRect();
    if (IsRectEmpty(&taskbar)) {
        ShowWindow(hwnd, SW_HIDE);
        return;
    }

    int taskbarWidth = taskbar.right - taskbar.left;
    int taskbarHeight = taskbar.bottom - taskbar.top;

    int width = g_settings.widgetWidth;
    int height = g_settings.widgetHeight;

    // For a vertical taskbar, center the widget horizontally in the taskbar
    // and place it near the top empty area.
    int x = taskbar.left + (taskbarWidth - width) / 2 + g_settings.offsetX;
    int y = taskbar.top + g_settings.offsetY;

    // If the taskbar is horizontal, keep it near the left/top as a fallback.
    if (taskbarWidth > taskbarHeight) {
        x = taskbar.left + g_settings.offsetX;
        y = taskbar.top + (taskbarHeight - height) / 2 + g_settings.offsetY;
    }

    if (g_hostedInTaskbar) {
        x -= taskbar.left;
        y -= taskbar.top;
    }

    SetWindowPos(
        hwnd,
        g_hostedInTaskbar ? HWND_TOP : HWND_TOPMOST,
        x,
        y,
        width,
        height,
        SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

static void DrawHeadsetIcon(HDC hdc, RECT iconRect, COLORREF color) {
    int cx = (iconRect.left + iconRect.right) / 2;
    int top = iconRect.top + 1;
    int bottom = iconRect.bottom - 2;

    HPEN pen = CreatePen(PS_SOLID, 2, color);
    HGDIOBJ oldPen = SelectObject(hdc, pen);
    HGDIOBJ oldBrush = SelectObject(hdc, GetStockObject(NULL_BRUSH));

    Arc(hdc, cx - 8, top, cx + 8, top + 18, cx - 8, top + 9, cx + 8, top + 9);
    RoundRect(hdc, cx - 11, bottom - 8, cx - 6, bottom, 3, 3);
    RoundRect(hdc, cx + 6, bottom - 8, cx + 11, bottom, 3, 3);

    SelectObject(hdc, oldBrush);
    SelectObject(hdc, oldPen);
    DeleteObject(pen);
}

static void DrawMonitorIcon(HDC hdc, RECT iconRect, COLORREF color) {
    int cx = (iconRect.left + iconRect.right) / 2;
    int top = iconRect.top + 3;

    HPEN pen = CreatePen(PS_SOLID, 2, color);
    HGDIOBJ oldPen = SelectObject(hdc, pen);
    HGDIOBJ oldBrush = SelectObject(hdc, GetStockObject(NULL_BRUSH));

    RoundRect(hdc, cx - 10, top, cx + 10, top + 12, 3, 3);
    MoveToEx(hdc, cx, top + 13, nullptr);
    LineTo(hdc, cx, top + 17);
    MoveToEx(hdc, cx - 6, top + 17, nullptr);
    LineTo(hdc, cx + 6, top + 17);

    SelectObject(hdc, oldBrush);
    SelectObject(hdc, oldPen);
    DeleteObject(pen);
}

static bool HasDetailedBattery() {
    return g_detailedBattery.left >= 0 ||
           g_detailedBattery.right >= 0;
}

static COLORREF BatteryLevelColor(int value, bool charging, COLORREF fg) {
    if (charging) {
        return RGB(86, 209, 255);
    }
    if (value >= 0 && value <= g_settings.lowBatteryPercent) {
        return RGB(255, 92, 92);
    }
    return fg;
}

static void DrawChargingBolt(HDC hdc, int x, int y, COLORREF color) {
    POINT bolt[] = {
        {x + 3, y},
        {x, y + 5},
        {x + 3, y + 5},
        {x + 1, y + 10},
        {x + 7, y + 3},
        {x + 4, y + 3},
    };

    HPEN pen = CreatePen(PS_SOLID, 1, color);
    HBRUSH brush = CreateSolidBrush(color);
    HGDIOBJ oldPen = SelectObject(hdc, pen);
    HGDIOBJ oldBrush = SelectObject(hdc, brush);
    Polygon(hdc, bolt, ARRAYSIZE(bolt));
    SelectObject(hdc, oldBrush);
    SelectObject(hdc, oldPen);
    DeleteObject(brush);
    DeleteObject(pen);
}

static void DrawBatteryPart(
    HDC hdc,
    int y,
    wchar_t label,
    int value,
    bool charging,
    COLORREF fg,
    COLORREF muted) {

    COLORREF color = BatteryLevelColor(value, charging, fg);

    HFONT labelFont = CreateFontW(
        -11,
        0,
        0,
        0,
        FW_SEMIBOLD,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH,
        L"Segoe UI");

    HGDIOBJ oldFont = SelectObject(hdc, labelFont);
    SetBkMode(hdc, TRANSPARENT);

    WCHAR labelText[4] = {label, 0};
    RECT labelRect = {0, y, g_settings.widgetWidth, y + 10};
    SetTextColor(hdc, muted);
    DrawTextW(hdc, labelText, -1, &labelRect, DT_CENTER | DT_SINGLELINE | DT_VCENTER);

    WCHAR valueText[8] = {};
    if (value >= 0) {
        StringCchPrintfW(valueText, ARRAYSIZE(valueText), L"%d", value);
    } else {
        StringCchCopyW(valueText, ARRAYSIZE(valueText), L"--");
    }

    SelectObject(hdc, oldFont);
    DeleteObject(labelFont);

    HFONT valueFont = CreateFontW(
        -20,
        0,
        0,
        0,
        FW_BOLD,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH,
        L"Segoe UI");

    oldFont = SelectObject(hdc, valueFont);
    SetTextColor(hdc, color);
    RECT valueRect = {0, y + 9, g_settings.widgetWidth - 6, y + 31};
    DrawTextW(hdc, valueText, -1, &valueRect, DT_RIGHT | DT_SINGLELINE | DT_VCENTER);

    HFONT percentFont = CreateFontW(
        -9,
        0,
        0,
        0,
        FW_BOLD,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH,
        L"Segoe UI");

    SIZE valueSize = {};
    GetTextExtentPoint32W(hdc, valueText, lstrlenW(valueText), &valueSize);
    SelectObject(hdc, percentFont);
    SetTextColor(hdc, muted);
    RECT percentRect = {
        std::max(0, static_cast<int>((g_settings.widgetWidth + valueSize.cx) / 2 - 4)),
        y + 18,
        g_settings.widgetWidth,
        y + 30,
    };
    DrawTextW(hdc, L"%", -1, &percentRect, DT_LEFT | DT_SINGLELINE | DT_VCENTER);

    if (charging && value >= 0) {
        DrawChargingBolt(hdc, g_settings.widgetWidth - 12, y + 2, RGB(86, 209, 255));
    }

    SelectObject(hdc, oldFont);
    DeleteObject(percentFont);
    DeleteObject(valueFont);
}

static void PaintWidget(HWND hwnd) {
    PAINTSTRUCT ps;
    HDC hdc = BeginPaint(hwnd, &ps);

    RECT rect = {};
    GetClientRect(hwnd, &rect);

    bool hasBattery = g_batteryPercent >= 0;
    bool isLow = hasBattery && g_batteryPercent <= g_settings.lowBatteryPercent;
    COLORREF fg = g_settings.darkBackground ? RGB(250, 250, 250) : RGB(24, 24, 24);
    COLORREF muted = g_settings.darkBackground ? RGB(175, 175, 175) : RGB(86, 86, 86);
    COLORREF batteryColor = isLow ? RGB(255, 92, 92) : fg;

    HBRUSH transparentBrush = CreateSolidBrush(RGB(1, 1, 1));
    FillRect(hdc, &rect, transparentBrush);
    DeleteObject(transparentBrush);

    RECT iconRect = rect;
    iconRect.top = rect.top + 2;
    iconRect.bottom = rect.top + 22;
    COLORREF iconColor = g_audioOutputState == 0 ? muted : fg;
    if (g_audioOutputState == 2) {
        DrawMonitorIcon(hdc, iconRect, iconColor);
    } else {
        DrawHeadsetIcon(hdc, iconRect, iconColor);
    }

    if (HasDetailedBattery()) {
        DrawBatteryPart(hdc, 25, L'L', g_detailedBattery.left, g_detailedBattery.leftCharging, fg, muted);
        DrawBatteryPart(hdc, 57, L'R', g_detailedBattery.right, g_detailedBattery.rightCharging, fg, muted);
        EndPaint(hwnd, &ps);
        return;
    }

    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, batteryColor);

    HFONT percentFont = CreateFontW(
        -12,
        0,
        0,
        0,
        FW_SEMIBOLD,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH,
        L"Segoe UI");

    HGDIOBJ oldFont = SelectObject(hdc, percentFont);

    WCHAR text[32] = {};
    if (hasBattery) {
        StringCchPrintfW(text, ARRAYSIZE(text), L"%d%%", g_batteryPercent);
    } else {
        StringCchCopyW(text, ARRAYSIZE(text), L"--");
    }

    RECT textRect = rect;
    textRect.top += 20;
    SetTextColor(hdc, batteryColor);
    DrawTextW(hdc, text, -1, &textRect, DT_CENTER | DT_SINGLELINE | DT_VCENTER);

    SelectObject(hdc, oldFont);
    DeleteObject(percentFont);

    EndPaint(hwnd, &ps);
}

static LRESULT CALLBACK WidgetWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE:
            SetTimer(hwnd, TIMER_POLL, static_cast<UINT>(std::max(5, g_settings.pollSeconds)) * 1000, nullptr);
            SetTimer(hwnd, TIMER_REPOSITION, 2000, nullptr);
            UpdateBattery(hwnd);
            UpdateDetailedBattery(hwnd);
            UpdateAudioOutputState(hwnd);
            RepositionWidget(hwnd);
            return 0;

        case WM_TIMER:
            if (wParam == TIMER_POLL) {
                UpdateBattery(hwnd);
                UpdateDetailedBattery(hwnd);
                UpdateAudioOutputState(hwnd);
            } else if (wParam == TIMER_REPOSITION) {
                RepositionWidget(hwnd);
            }
            return 0;

        case WM_PAINT:
            PaintWidget(hwnd);
            return 0;

        case WM_ERASEBKGND:
            return 1;

        case WM_LBUTTONUP:
            PlaySoundW(L"SystemAsterisk", nullptr, SND_ALIAS | SND_ASYNC);
            return 0;

        case WM_RBUTTONUP:
            ShowActionMenu(hwnd);
            return 0;

        case WM_COMMAND:
            if (LOWORD(wParam) == MENU_TEST_SOUND) {
                PlaySoundW(L"SystemAsterisk", nullptr, SND_ALIAS | SND_ASYNC);
            } else if (LOWORD(wParam) == MENU_TOGGLE_OUTPUT) {
                ToggleAudioOutput();
            }
            return 0;

        case WM_DESTROY:
            KillTimer(hwnd, TIMER_POLL);
            KillTimer(hwnd, TIMER_REPOSITION);
            return 0;
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static DWORD WINAPI WidgetThreadProc(LPVOID) {
    HINSTANCE instance = GetModuleHandleW(nullptr);

    WNDCLASSW wc = {};
    wc.lpfnWndProc = WidgetWndProc;
    wc.hInstance = instance;
    wc.lpszClassName = WIDGET_CLASS_NAME;
    wc.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));

    RegisterClassW(&wc);

    HWND taskbar = g_settings.hostInTaskbar ? GetTaskbarWindow() : nullptr;
    g_hostedInTaskbar = taskbar != nullptr;
    DWORD style = g_hostedInTaskbar ? (WS_CHILD | WS_VISIBLE) : WS_POPUP;
    DWORD exStyle = WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
    if (!g_hostedInTaskbar) {
        exStyle |= WS_EX_TOPMOST;
    }

    g_widgetWindow = CreateWindowExW(
        exStyle,
        WIDGET_CLASS_NAME,
        L"Headset Battery",
        style,
        0,
        0,
        g_settings.widgetWidth,
        g_settings.widgetHeight,
        taskbar,
        nullptr,
        instance,
        nullptr);

    if (!g_widgetWindow) {
        return 0;
    }

    if (!g_hostedInTaskbar) {
        SetWindowLongW(
            g_widgetWindow,
            GWL_EXSTYLE,
            GetWindowLongW(g_widgetWindow, GWL_EXSTYLE) | WS_EX_LAYERED);
        SetLayeredWindowAttributes(g_widgetWindow, RGB(1, 1, 1), 255, LWA_COLORKEY);
    }

    MSG msg;
    while (g_running && GetMessageW(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    if (g_widgetWindow) {
        DestroyWindow(g_widgetWindow);
        g_widgetWindow = nullptr;
    }

    return 0;
}

static void LoadSettings() {
    PCWSTR pattern = Wh_GetStringSetting(L"DeviceNamePattern");
    g_settings.deviceNamePattern = pattern ? pattern : L"";
    if (pattern) {
        Wh_FreeStringSetting(pattern);
    }

    g_settings.pollSeconds = Wh_GetIntSetting(L"PollSeconds");
    g_settings.lowBatteryPercent = Wh_GetIntSetting(L"LowBatteryPercent");
    g_settings.alertSound = Wh_GetIntSetting(L"AlertSound") != 0;
    g_settings.widgetWidth = Wh_GetIntSetting(L"WidgetWidth");
    g_settings.widgetHeight = Wh_GetIntSetting(L"WidgetHeight");
    g_settings.offsetX = Wh_GetIntSetting(L"OffsetX");
    g_settings.offsetY = Wh_GetIntSetting(L"OffsetY");
    g_settings.darkBackground = Wh_GetIntSetting(L"DarkBackground") != 0;
    g_settings.hostInTaskbar = Wh_GetIntSetting(L"HostInTaskbar") != 0;

    PCWSTR primaryOutput = Wh_GetStringSetting(L"PrimaryOutputNamePattern");
    g_settings.primaryOutputNamePattern = primaryOutput ? primaryOutput : L"";
    if (primaryOutput) {
        Wh_FreeStringSetting(primaryOutput);
    }

    PCWSTR secondaryOutput = Wh_GetStringSetting(L"SecondaryOutputNamePattern");
    g_settings.secondaryOutputNamePattern = secondaryOutput ? secondaryOutput : L"";
    if (secondaryOutput) {
        Wh_FreeStringSetting(secondaryOutput);
    }

    PCWSTR detailedBatteryFile = Wh_GetStringSetting(L"DetailedBatteryFile");
    g_settings.detailedBatteryFile = detailedBatteryFile ? detailedBatteryFile : L"";
    if (detailedBatteryFile) {
        Wh_FreeStringSetting(detailedBatteryFile);
    }

    if (g_settings.pollSeconds < 5) {
        g_settings.pollSeconds = 5;
    }
    if (g_settings.lowBatteryPercent < 1 || g_settings.lowBatteryPercent > 100) {
        g_settings.lowBatteryPercent = 30;
    }
    if (g_settings.widgetWidth < 32) {
        g_settings.widgetWidth = 48;
    }
    if (g_settings.widgetHeight < 28) {
        g_settings.widgetHeight = 64;
    }
}

BOOL Wh_ModInit() {
    LoadSettings();
    g_running = true;
    g_thread = CreateThread(nullptr, 0, WidgetThreadProc, nullptr, 0, &g_threadId);
    g_pipeThread = CreateThread(nullptr, 0, PipeThreadProc, nullptr, 0, &g_pipeThreadId);
    return TRUE;
}

void Wh_ModUninit() {
    g_running = false;

    if (g_widgetWindow) {
        PostMessageW(g_widgetWindow, WM_CLOSE, 0, 0);
    }

    if (g_threadId) {
        PostThreadMessageW(g_threadId, WM_QUIT, 0, 0);
    }

    if (g_thread) {
        WaitForSingleObject(g_thread, 3000);
        CloseHandle(g_thread);
        g_thread = nullptr;
        g_threadId = 0;
    }

    if (g_pipeThread) {
        if (WaitForSingleObject(g_pipeThread, 3000) == WAIT_TIMEOUT) {
            TerminateThread(g_pipeThread, 0);
        }
        CloseHandle(g_pipeThread);
        g_pipeThread = nullptr;
        g_pipeThreadId = 0;
    }
}

void Wh_ModSettingsChanged() {
    LoadSettings();
    if (g_widgetWindow) {
        SetTimer(g_widgetWindow, TIMER_POLL, static_cast<UINT>(std::max(5, g_settings.pollSeconds)) * 1000, nullptr);
        UpdateBattery(g_widgetWindow);
        UpdateDetailedBattery(g_widgetWindow);
        UpdateAudioOutputState(g_widgetWindow);
        RepositionWidget(g_widgetWindow);
        InvalidateRect(g_widgetWindow, nullptr, TRUE);
    }
}
