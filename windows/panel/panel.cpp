// windows/panel/panel.cpp — বাঙলা কিবোর্ড preview panel (MinGW-w64 g++, x64).
//
// A native Win32 window hosting Microsoft Edge WebView2 that loads the SAME shared UI as the
// macOS (WKWebView) and Linux (WebKitGTK) twins: ui\index.html, resolved next to the exe, at a
// 600x680 client area. Self-contained web app -> the panel needs no engine of its own.
//
// Hand-rolled raw-COM completion handlers (NO WRL: mingw-w64 lacks <wrl/implements.h>).
// The loader export is reached via LoadLibraryW+GetProcAddress, so NO WebView2 import library is
// linked — the only WebView2 build input is the header include path.
//
// IIDs: compared against LOCAL GUID constants via InlineIsEqualGUID — NOT __uuidof. Under mingw-w64
// __uuidof is a template backed by __CRT_UUID_DECL; WebView2.h's MIDL_INTERFACE structs are not
// declared that way, so __uuidof(ICoreWebView2...) is unreliable/undefined there. Local constants +
// InlineIsEqualGUID (guiddef.h) always work and need no -luuid and no EXTERN_C IID_* symbols.
//
// Build: see the g++ line at the bottom of this file (also in windows/build-all.sh).
#include <windows.h>
#include <objbase.h>          // CoInitializeEx / CoUninitialize / CoTaskMemFree
#include <shlwapi.h>          // UrlCreateFromPathW, PathFileExistsW   (-lshlwapi)
#include <string>
#include <cwchar>             // wcsrchr (do not rely on windows.h to expose it)
#include "WebView2.h"         // Microsoft.Web.WebView2 nupkg: build/native/include (classic COM)

// ---- runtime signatures of the two loader exports (declared STDAPI in WebView2.h) ----
typedef HRESULT (STDMETHODCALLTYPE *CreateEnvFn)(
    PCWSTR, PCWSTR, ICoreWebView2EnvironmentOptions*,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler*);
typedef HRESULT (STDMETHODCALLTYPE *GetVersionFn)(PCWSTR, LPWSTR*);

// ---- local IIDs (copied from WebView2.h MIDL_INTERFACE strings + IUnknown) ----
static const IID kIID_IUnknown =
    {0x00000000,0x0000,0x0000,{0xc0,0x00,0x00,0x00,0x00,0x00,0x00,0x46}};
static const IID kIID_EnvHandler =   // ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler
    {0x4e8a3389,0xc9d8,0x4bd2,{0xb6,0xb5,0x12,0x4f,0xee,0x6c,0xc1,0x4d}};
static const IID kIID_CtrlHandler =  // ICoreWebView2CreateCoreWebView2ControllerCompletedHandler
    {0x6c4819f3,0xc9b7,0x4260,{0x81,0x27,0xc9,0xf5,0xbd,0xe7,0xf6,0x8c}};

static ICoreWebView2Controller* g_controller = nullptr;
static ICoreWebView2*           g_webview    = nullptr;
static std::wstring             g_startUrl;
static bool                     g_haveIndex  = false;

static const wchar_t* kTitle = L"বাঙলা কিবোর্ড";
static const wchar_t* kMissingHtml =
    L"<body style='font-family:Segoe UI,sans-serif;padding:24px;color:#333'>"
    L"<h2>বাঙলা কিবোর্ড</h2><p>UI files not found "
    L"(expected ui\\index.html next to the app).</p></body>";

static void errBox(HWND h, const wchar_t* msg) {
    MessageBoxW(h, msg, kTitle, MB_ICONERROR | MB_OK);
}

// ---------- controller-created completion handler (hand-rolled COM) ----------
class CtrlHandler : public ICoreWebView2CreateCoreWebView2ControllerCompletedHandler {
    LONG m_ref = 1; HWND m_hwnd;
public:
    explicit CtrlHandler(HWND h) : m_hwnd(h) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (InlineIsEqualGUID(riid, kIID_IUnknown) ||
            InlineIsEqualGUID(riid, kIID_CtrlHandler)) {
            *ppv = static_cast<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler*>(this);
            AddRef(); return S_OK;
        }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return InterlockedIncrement(&m_ref); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG c = InterlockedDecrement(&m_ref); if (c == 0) delete this; return c;
    }
    HRESULT STDMETHODCALLTYPE Invoke(HRESULT ec, ICoreWebView2Controller* controller) override {
        if (FAILED(ec) || !controller) {
            errBox(m_hwnd, L"WebView2 controller could not be created.");
            return ec;
        }
        controller->AddRef(); g_controller = controller;
        g_controller->get_CoreWebView2(&g_webview);      // out-param arrives AddRef'd
        RECT rc; GetClientRect(m_hwnd, &rc);
        g_controller->put_Bounds(rc);
        g_controller->put_IsVisible(TRUE);
        if (g_webview) {
            if (g_haveIndex) g_webview->Navigate(g_startUrl.c_str());
            else             g_webview->NavigateToString(kMissingHtml);
        }
        return S_OK;
    }
};

// ---------- environment-created completion handler (hand-rolled COM) ----------
class EnvHandler : public ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler {
    LONG m_ref = 1; HWND m_hwnd;
public:
    explicit EnvHandler(HWND h) : m_hwnd(h) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (InlineIsEqualGUID(riid, kIID_IUnknown) ||
            InlineIsEqualGUID(riid, kIID_EnvHandler)) {
            *ppv = static_cast<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler*>(this);
            AddRef(); return S_OK;
        }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef()  override { return InterlockedIncrement(&m_ref); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG c = InterlockedDecrement(&m_ref); if (c == 0) delete this; return c;
    }
    HRESULT STDMETHODCALLTYPE Invoke(HRESULT ec, ICoreWebView2Environment* env) override {
        if (FAILED(ec) || !env) {
            errBox(m_hwnd, L"WebView2 environment could not be created.\n"
                           L"Install the Microsoft Edge WebView2 Runtime (Evergreen).");
            return ec;
        }
        CtrlHandler* ch = new CtrlHandler(m_hwnd);         // ref = 1
        env->CreateCoreWebView2Controller(m_hwnd, ch);     // API AddRefs -> 2
        ch->Release();                                     // -> 1, freed after its Invoke
        return S_OK;
    }
};

// Resolve ui\index.html next to the exe and percent-encode it into a file:/// URL.
// UrlCreateFromPathW handles the space in "C:\Program Files\..." that naive concat would break.
static void resolveStartUrl() {
    wchar_t exe[MAX_PATH]; GetModuleFileNameW(nullptr, exe, MAX_PATH);
    wchar_t* slash = wcsrchr(exe, L'\\'); if (slash) *(slash + 1) = 0;
    std::wstring idx = std::wstring(exe) + L"ui\\index.html";
    g_haveIndex = (PathFileExistsW(idx.c_str()) == TRUE);
    wchar_t url[4096]; DWORD len = 4096;    // INTERNET_MAX_URL_LENGTH lives in <wininet.h>; avoid it
    if (SUCCEEDED(UrlCreateFromPathW(idx.c_str(), url, &len, 0))) g_startUrl = url;
    else g_haveIndex = false;
}

// Explicit %LOCALAPPDATA% user-data folder — the default (<exe>.WebView2 next to the exe) is
// unwritable if the app ever lands under Program Files, and env creation fails E_ACCESSDENIED.
static std::wstring userDataFolder() {
    wchar_t buf[MAX_PATH]; DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", buf, MAX_PATH);
    std::wstring base = (n > 0 && n < MAX_PATH) ? std::wstring(buf) : std::wstring(L".");
    return base + L"\\BanglaKeyboard\\WebView2";
}

static void startWebView(HWND hwnd) {
    HMODULE loader = LoadLibraryW(L"WebView2Loader.dll");   // ships next to bangla-panel.exe
    if (!loader) { errBox(hwnd, L"WebView2Loader.dll was not found next to the app.\n"
                                L"Please reinstall Bangla Keyboard."); return; }
    auto create = reinterpret_cast<CreateEnvFn>(
        GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions"));
    if (!create) { errBox(hwnd, L"WebView2Loader.dll is missing its entry point."); return; }

    // Proactive Evergreen-Runtime probe (the loader != the Runtime).
    auto getver = reinterpret_cast<GetVersionFn>(
        GetProcAddress(loader, "GetAvailableCoreWebView2BrowserVersionString"));
    if (getver) {
        LPWSTR ver = nullptr;
        HRESULT vhr = getver(nullptr, &ver);
        bool present = SUCCEEDED(vhr) && ver && ver[0];
        if (ver) CoTaskMemFree(ver);
        if (!present) {
            errBox(hwnd, L"The Microsoft Edge WebView2 Runtime is not installed.\n"
                         L"Install the Evergreen Runtime, then reopen Bangla Keyboard.");
            return;
        }
    }

    std::wstring udf = userDataFolder();
    EnvHandler* eh = new EnvHandler(hwnd);                  // ref = 1
    HRESULT hr = create(nullptr, udf.c_str(), nullptr, eh); // env options = nullptr (no WRL needed)
    eh->Release();                                          // API holds its own ref
    if (FAILED(hr))
        errBox(hwnd, L"Failed to start WebView2 (is the Edge WebView2 Runtime installed?).");
}

static LRESULT CALLBACK WndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_SIZE:
        if (g_controller) { RECT rc; GetClientRect(h, &rc); g_controller->put_Bounds(rc); }
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, LPWSTR, int nCmdShow) {
    SetProcessDPIAware();
    HRESULT hrCo = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);  // WebView2 wants an STA
    resolveStartUrl();

    WNDCLASSW wc = {};
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInst;
    wc.hIcon         = LoadIconW(hInst, MAKEINTRESOURCEW(1));   // app icon from panel.rc
    wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = L"BanglaKeyboardPanel";
    RegisterClassW(&wc);

    const DWORD style = WS_OVERLAPPEDWINDOW;
    RECT r = { 0, 0, 600, 680 }; AdjustWindowRect(&r, style, FALSE);  // 600x680 CLIENT area
    const int w = r.right - r.left, hgt = r.bottom - r.top;
    const int x = (GetSystemMetrics(SM_CXSCREEN) - w) / 2;
    const int y = (GetSystemMetrics(SM_CYSCREEN) - hgt) / 2;

    HWND hwnd = CreateWindowW(wc.lpszClassName, kTitle, style,
                             x, y, w, hgt, nullptr, nullptr, hInst, nullptr);
    ShowWindow(hwnd, nCmdShow); UpdateWindow(hwnd);
    startWebView(hwnd);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageW(&msg); }

    if (g_webview)    g_webview->Release();
    if (g_controller) g_controller->Release();
    if (SUCCEEDED(hrCo)) CoUninitialize();
    return (int)msg.wParam;
}

/* g++ (msys2 MINGW64), x64 only — mirrors windows/tray build flags:
   windres windows/panel/panel.rc -o windows/panel/panel_res.o
   g++ -std=c++17 -O2 -static -mwindows -municode -DUNICODE -D_UNICODE -finput-charset=UTF-8 \
       -I windows/vendor/webview2/build/native/include \
       windows/panel/panel.cpp windows/panel/panel_res.o -o windows/dist/bangla-panel.exe \
       -lole32 -lshlwapi -lshell32 -luser32 -lgdi32
   No WebView2 .lib is linked (loader reached via LoadLibraryW+GetProcAddress); no -luuid
   (IIDs are local constants compared with InlineIsEqualGUID).
   Ship windows/vendor/webview2/build/native/x64/WebView2Loader.dll next to the exe. */