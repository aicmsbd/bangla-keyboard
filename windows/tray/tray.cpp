// বাঙলা কিবোর্ড — Windows tray keyboard (phonetic "Banglish", the twin of the macOS app).
//
// A background app with a system-tray icon. A global low-level keyboard hook runs each keystroke
// through the SHARED phonetic engine (../../engine/phonetic), transliterates Banglish -> Bangla,
// and injects it with SendInput so it types Bangla in ANY app — no IME registration, no admin.
// While a word is in progress it shows a suggestion popup (offline dictionary + AiCMS hard-word
// aliases); press 1..6 to pick a word. Same engine + dictionary as the macOS build.
//
//   English  — passthrough.
//   বাংলা     — phonetic Banglish (type "amar" -> আমার), with live suggestions.
//
// Toggle with the tray icon, the menu, or Ctrl+Alt+B.
//
// Build (MSYS2/mingw): g++ -std=c++17 -O2 -static -mwindows -municode -finput-charset=UTF-8 \
//        tray.cpp -o ../dist/bangla-tray.exe -lgdi32 -luser32 -lshell32
// The dictionary files (bangla-dictionary.txt, hardwords_raw.tsv) ship next to the .exe.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <string>
#include <vector>
#include "../../engine/phonetic/phonetic.hpp"
#include "../../engine/phonetic/worddb.hpp"

#ifndef LOAD_LIBRARY_SEARCH_SYSTEM32
#define LOAD_LIBRARY_SEARCH_SYSTEM32 0x00000800
#endif

using Str = std::u16string;
using banglaphon::transliterate;

enum Mode { MODE_ENGLISH = 0, MODE_BANGLA = 1 };

// ---- state -----------------------------------------------------------------
static HINSTANCE       g_hInst;
static HWND            g_hWnd;
static HHOOK           g_hook;
static Mode            g_mode = MODE_ENGLISH;
static std::string     g_roman;            // ASCII typed so far in the current word
static Str             g_shown;            // Bangla currently on screen for the current word
static banglaphon::WordDB g_db;
static bool            g_dbReady = false;
static NOTIFYICONDATAW g_nid    = {};
static HICON           g_icoBn  = nullptr; // অ on flag-red circle
static HICON           g_icoEn  = nullptr; // E on grey circle
static HBITMAP         g_bmpBn  = nullptr; // 16x16 for the popup menu
static HBITMAP         g_bmpEn  = nullptr;

// suggestion popup
static HWND            g_pop = nullptr;
static std::vector<Str> g_cands;
static HFONT           g_popFont = nullptr;

#define WM_TRAY       (WM_APP + 1)
#define ID_BANGLA       1001
#define ID_ENGLISH      1003
#define ID_ABOUT        1010
#define ID_EXIT         1011
#define HOTKEY_BANGLA   1   // Ctrl+Alt+B -> বাংলা
#define HOTKEY_ENGLISH  2   // Ctrl+Alt+E -> English (matches the macOS ⌃B / ⌃E scheme)

// ---- key injection ---------------------------------------------------------
static void sendBackspaces(int n) {
    if (n <= 0) return;
    std::vector<INPUT> in; in.reserve(n * 2);
    for (int i = 0; i < n; ++i) {
        INPUT d = {}; d.type = INPUT_KEYBOARD; d.ki.wVk = VK_BACK; in.push_back(d);
        INPUT u = {}; u.type = INPUT_KEYBOARD; u.ki.wVk = VK_BACK; u.ki.dwFlags = KEYEVENTF_KEYUP; in.push_back(u);
    }
    SendInput((UINT)in.size(), in.data(), sizeof(INPUT));
}
static void sendUnicode(const Str& s) {
    if (s.empty()) return;
    std::vector<INPUT> in; in.reserve(s.size() * 2);
    for (char16_t c : s) {
        INPUT d = {}; d.type = INPUT_KEYBOARD; d.ki.wScan = c; d.ki.dwFlags = KEYEVENTF_UNICODE; in.push_back(d);
        INPUT u = {}; u.type = INPUT_KEYBOARD; u.ki.wScan = c; u.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP; in.push_back(u);
    }
    SendInput((UINT)in.size(), in.data(), sizeof(INPUT));
}

// Replace what's on screen with `next` by back-spacing only the changed suffix and retyping it.
static void replaceShown(const Str& next) {
    size_t i = 0;
    while (i < g_shown.size() && i < next.size() && g_shown[i] == next[i]) ++i;
    sendBackspaces((int)(g_shown.size() - i));
    sendUnicode(next.substr(i));
    g_shown = next;
}

// ---- suggestion popup ------------------------------------------------------
static POINT caretScreenPos() {
    GUITHREADINFO gui = {}; gui.cbSize = sizeof(gui);
    DWORD tid = GetWindowThreadProcessId(GetForegroundWindow(), nullptr);
    if (GetGUIThreadInfo(tid, &gui) && gui.hwndCaret) {
        POINT p = { gui.rcCaret.left, gui.rcCaret.bottom };
        if (ClientToScreen(gui.hwndCaret, &p)) return p;
    }
    POINT c; GetCursorPos(&c); c.y += 18; return c;   // fallback: just under the cursor
}

static void hideCandidates() {
    g_cands.clear();
    if (g_pop) ShowWindow(g_pop, SW_HIDE);
}

static void showCandidates() {
    if (!g_pop) return;
    if (g_cands.empty()) { hideCandidates(); return; }
    // size to fit the rendered text
    HDC dc = GetDC(g_pop);
    HGDIOBJ of = SelectObject(dc, g_popFont);
    std::wstring line;
    for (size_t i = 0; i < g_cands.size(); ++i) {
        if (i) line += L"   ";
        line += std::to_wstring(i + 1) + L" ";
        line += std::wstring(g_cands[i].begin(), g_cands[i].end());  // BMP Bangla: u16 == wchar_t
    }
    SIZE sz = {}; GetTextExtentPoint32W(dc, line.c_str(), (int)line.size(), &sz);
    SelectObject(dc, of); ReleaseDC(g_pop, dc);
    int w = sz.cx + 20, h = sz.cy + 12;
    POINT p = caretScreenPos();
    // clamp onto the monitor that holds the caret
    HMONITOR mon = MonitorFromPoint(p, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = {}; mi.cbSize = sizeof(mi); GetMonitorInfoW(mon, &mi);
    int x = p.x, y = p.y + 2;
    if (x + w > mi.rcWork.right)  x = mi.rcWork.right - w - 2;
    if (x < mi.rcWork.left)       x = mi.rcWork.left + 2;
    if (y + h > mi.rcWork.bottom) y = p.y - h - 18;            // no room below -> above the caret
    SetWindowPos(g_pop, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE);
    ShowWindow(g_pop, SW_SHOWNOACTIVATE);
    InvalidateRect(g_pop, nullptr, TRUE);
}

static LRESULT CALLBACK popProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_PAINT) {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps);
        RECT rc; GetClientRect(h, &rc);
        HBRUSH bg = CreateSolidBrush(RGB(28, 30, 38));
        FillRect(dc, &rc, bg); DeleteObject(bg);
        SetBkMode(dc, TRANSPARENT);
        HGDIOBJ of = SelectObject(dc, g_popFont);
        int x = 10;
        for (size_t i = 0; i < g_cands.size(); ++i) {
            std::wstring num = std::to_wstring(i + 1) + L" ";
            SetTextColor(dc, RGB(150, 156, 168));
            TextOutW(dc, x, 6, num.c_str(), (int)num.size());
            SIZE ns; GetTextExtentPoint32W(dc, num.c_str(), (int)num.size(), &ns); x += ns.cx;
            std::wstring w(g_cands[i].begin(), g_cands[i].end());
            SetTextColor(dc, RGB(245, 246, 250));
            TextOutW(dc, x, 6, w.c_str(), (int)w.size());
            SIZE ws; GetTextExtentPoint32W(dc, w.c_str(), (int)w.size(), &ws); x += ws.cx;
            std::wstring gap = L"   ";
            SIZE gs; GetTextExtentPoint32W(dc, gap.c_str(), (int)gap.size(), &gs); x += gs.cx;
        }
        SelectObject(dc, of);
        EndPaint(h, &ps);
        return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

// ---- phonetic engine glue --------------------------------------------------
static void pFlush() {                    // commit the current word (space/Enter/focus loss)
    g_roman.clear();
    g_shown.clear();
    hideCandidates();
}
static void pUpdateCandidates() {
    if (!g_dbReady || g_roman.empty()) { hideCandidates(); return; }
    auto res = g_db.lookup(g_roman, 6);
    g_cands.assign(res.begin(), res.end());
    showCandidates();
}
static void pRepaint() {                   // transliterate the whole roman buffer and show it
    replaceShown(transliterate(g_roman));
    pUpdateCandidates();
}
static void pCommit(const Str& word) {     // a suggestion was picked: replace + finalise
    replaceShown(word);
    pFlush();
}

// The ASCII scheme char a key would type (US layout), or 0 if it's a word boundary. Case matters
// (phonetic is case-sensitive: S->ষ, s->স). Digits and ^ . ` are in-word, matching the engine.
static char phoneticChar(DWORD vk, bool shift) {
    if (vk >= 'A' && vk <= 'Z') return shift ? (char)vk : (char)(vk + 32);
    if (vk >= '0' && vk <= '9') { if (!shift) return (char)vk; if (vk == '6') return '^'; return 0; }
    if (vk == VK_OEM_PERIOD && !shift) return '.';    // danda ।
    if (vk == VK_OEM_3     && !shift) return '`';     // hasanta / khanda-ta
    return 0;
}

// ---- the global keyboard hook ----------------------------------------------
static LRESULT CALLBACK hookProc(int code, WPARAM wParam, LPARAM lParam) {
    bool eat = false;
    if (code == HC_ACTION && g_mode == MODE_BANGLA) {
        try {
            auto* k = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
            bool injected = (k->flags & LLKHF_INJECTED) != 0;     // skip our own SendInput
            if (!injected && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
                auto down = [](int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; };
                bool ctrl = down(VK_CONTROL), alt = down(VK_MENU), win = down(VK_LWIN) || down(VK_RWIN);
                bool shift = down(VK_SHIFT);
                DWORD vk = k->vkCode;
                bool isModifier = vk == VK_SHIFT || vk == VK_LSHIFT || vk == VK_RSHIFT
                               || vk == VK_CONTROL || vk == VK_LCONTROL || vk == VK_RCONTROL
                               || vk == VK_MENU || vk == VK_LMENU || vk == VK_RMENU
                               || vk == VK_LWIN || vk == VK_RWIN || vk == VK_CAPITAL;

                if (isModifier) {
                    /* keep the in-progress word */
                } else if (ctrl || alt || win) {
                    pFlush();                                     // let the shortcut through
                } else if (vk == VK_BACK) {
                    if (!g_roman.empty()) { g_roman.pop_back(); pRepaint(); eat = true; }
                    else pFlush();
                } else if (vk == VK_ESCAPE && !g_cands.empty()) {
                    hideCandidates(); eat = true;                 // just dismiss the popup
                } else {
                    char c = phoneticChar(vk, shift);
                    if (!g_cands.empty() && c >= '1' && c <= '9'
                        && (size_t)(c - '1') < g_cands.size()) {
                        pCommit(g_cands[c - '1']); eat = true;    // pick a suggestion
                    } else if (c) {
                        g_roman.push_back(c); pRepaint(); eat = true;
                    } else {
                        pFlush();                                 // space/Enter/Tab/etc. -> boundary
                    }
                }
            }
        } catch (...) { g_roman.clear(); g_shown.clear(); g_cands.clear(); }
    }
    if (eat) return 1;
    return CallNextHookEx(g_hook, code, wParam, lParam);
}

// ---- tray icon / menu ------------------------------------------------------
static HICON makeIcon(const wchar_t* txt, COLORREF circle, COLORREF fg) {
    const int sz = 32;
    HDC sdc = GetDC(nullptr);
    HDC dc  = CreateCompatibleDC(sdc);
    HBITMAP color = CreateCompatibleBitmap(sdc, sz, sz);
    HBITMAP mask  = CreateBitmap(sz, sz, 1, 1, nullptr);
    HGDIOBJ ob = SelectObject(dc, color);
    RECT r = {0, 0, sz, sz};
    HBRUSH green = CreateSolidBrush(RGB(0, 106, 78));
    FillRect(dc, &r, green); DeleteObject(green);
    HBRUSH cb = CreateSolidBrush(circle);
    HGDIOBJ ob2 = SelectObject(dc, cb);
    HGDIOBJ op  = SelectObject(dc, GetStockObject(NULL_PEN));
    Ellipse(dc, 3, 3, sz - 3, sz - 3);
    SelectObject(dc, op); SelectObject(dc, ob2); DeleteObject(cb);
    SetBkMode(dc, TRANSPARENT); SetTextColor(dc, fg);
    HFONT f = CreateFontW(22, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET,
                          OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                          DEFAULT_PITCH, L"Nirmala UI");
    HGDIOBJ of = SelectObject(dc, f);
    DrawTextW(dc, txt, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    SelectObject(dc, of); DeleteObject(f);
    SelectObject(dc, ob);
    ICONINFO ii = {}; ii.fIcon = TRUE; ii.hbmColor = color; ii.hbmMask = mask;
    HICON ic = CreateIconIndirect(&ii);
    DeleteObject(color); DeleteObject(mask); DeleteDC(dc); ReleaseDC(nullptr, sdc);
    return ic;
}
static HBITMAP makeMenuBitmap(const wchar_t* txt, COLORREF circle, COLORREF fg) {
    const int sz = 16;
    HDC sdc = GetDC(nullptr);
    HDC dc  = CreateCompatibleDC(sdc);
    HBITMAP bmp = CreateCompatibleBitmap(sdc, sz, sz);
    HGDIOBJ ob = SelectObject(dc, bmp);
    RECT r = {0, 0, sz, sz};
    HBRUSH green = CreateSolidBrush(RGB(0, 106, 78));
    FillRect(dc, &r, green); DeleteObject(green);
    HBRUSH cb = CreateSolidBrush(circle);
    HGDIOBJ ob2 = SelectObject(dc, cb);
    HGDIOBJ op  = SelectObject(dc, GetStockObject(NULL_PEN));
    Ellipse(dc, 1, 1, sz - 1, sz - 1);
    SelectObject(dc, op); SelectObject(dc, ob2); DeleteObject(cb);
    SetBkMode(dc, TRANSPARENT); SetTextColor(dc, fg);
    HFONT f = CreateFontW(13, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET,
                          OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                          DEFAULT_PITCH, L"Nirmala UI");
    HGDIOBJ of = SelectObject(dc, f);
    DrawTextW(dc, txt, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    SelectObject(dc, of); DeleteObject(f);
    SelectObject(dc, ob); DeleteDC(dc); ReleaseDC(nullptr, sdc);
    return bmp;
}

// Load the app's real logo (icon resource 1 = banglakeyboard.ico) at a given size.
static HICON loadLogoIcon(int sz) {
    return (HICON)LoadImageW(g_hInst, MAKEINTRESOURCEW(1), IMAGE_ICON, sz, sz, LR_DEFAULTCOLOR);
}
// Composite an HICON into an HBITMAP for a popup-menu item (over the menu background).
static HBITMAP iconToMenuBitmap(HICON ico, int sz) {
    HDC sdc = GetDC(nullptr);
    HDC dc  = CreateCompatibleDC(sdc);
    HBITMAP bmp = CreateCompatibleBitmap(sdc, sz, sz);
    HGDIOBJ ob = SelectObject(dc, bmp);
    RECT r = {0, 0, sz, sz};
    FillRect(dc, &r, GetSysColorBrush(COLOR_MENU));
    if (ico) DrawIconEx(dc, 0, 0, ico, sz, sz, 0, nullptr, DI_NORMAL);
    SelectObject(dc, ob); DeleteDC(dc); ReleaseDC(nullptr, sdc);
    return bmp;
}

static const wchar_t* modeTip() {
    return g_mode == MODE_BANGLA
        ? L"বাঙলা কিবোর্ড — বাংলা (Banglish)  ·  Ctrl+Alt+E = English"
        : L"বাঙলা কিবোর্ড — English  ·  Ctrl+Alt+B = বাংলা";
}
static void updateTray() {
    g_nid.hIcon = (g_mode == MODE_BANGLA) ? g_icoBn : g_icoEn;
    lstrcpynW(g_nid.szTip, modeTip(), ARRAYSIZE(g_nid.szTip));
    Shell_NotifyIconW(NIM_MODIFY, &g_nid);
}
static void setMode(Mode m) {
    if (g_mode == m) return;
    pFlush();
    g_mode = m;
    updateTray();
}
static void toggleMode() { setMode(g_mode == MODE_BANGLA ? MODE_ENGLISH : MODE_BANGLA); }

static void showMenu() {
    POINT pt; GetCursorPos(&pt);
    HMENU m = CreatePopupMenu();
    AppendMenuW(m, MF_STRING | (g_mode == MODE_BANGLA  ? MF_CHECKED : 0), ID_BANGLA,  L"বাংলা (Banglish)");
    AppendMenuW(m, MF_STRING | (g_mode == MODE_ENGLISH ? MF_CHECKED : 0), ID_ENGLISH, L"English");
    auto setBmp = [&](UINT id, HBITMAP b) {
        MENUITEMINFOW mii = {}; mii.cbSize = sizeof(mii); mii.fMask = MIIM_BITMAP; mii.hbmpItem = b;
        SetMenuItemInfoW(m, id, FALSE, &mii);
    };
    setBmp(ID_BANGLA, g_bmpBn);
    setBmp(ID_ENGLISH, g_bmpEn);
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(m, MF_STRING, ID_ABOUT, L"About");
    AppendMenuW(m, MF_STRING, ID_EXIT, L"Close");
    SetForegroundWindow(g_hWnd);
    TrackPopupMenu(m, TPM_RIGHTBUTTON, pt.x, pt.y, 0, g_hWnd, nullptr);
    DestroyMenu(m);
}

static LRESULT CALLBACK wndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_TRAY:
            if (LOWORD(lp) == WM_RBUTTONUP || LOWORD(lp) == WM_CONTEXTMENU) showMenu();
            else if (LOWORD(lp) == WM_LBUTTONUP) toggleMode();
            return 0;
        case WM_COMMAND:
            switch (LOWORD(wp)) {
                case ID_BANGLA:  setMode(MODE_BANGLA);  break;
                case ID_ENGLISH: setMode(MODE_ENGLISH); break;
                case ID_ABOUT:
                    MessageBoxW(h,
                        L"বাঙলা কিবোর্ড — phonetic Bangla keyboard\n\n"
                        L"বাংলা = type Banglish (amar -> আমার) in any app, with live suggestions.\n"
                        L"English = normal typing.\n\n"
                        L"Switch: Ctrl+Alt+B = বাংলা, Ctrl+Alt+E = English (or click the tray icon).\n"
                        L"While typing, press 1–6 to pick a suggested word.\n\n"
                        L"Same engine + dictionary as the macOS build. Fully offline.\n"
                        L"Powered By AiCMS.BD • AICMS Public License v1.0.",
                        L"About বাঙলা কিবোর্ড", MB_OK | MB_ICONINFORMATION);
                    break;
                case ID_EXIT: DestroyWindow(h); break;
            }
            return 0;
        case WM_HOTKEY:
            if      (wp == HOTKEY_BANGLA)  setMode(MODE_BANGLA);
            else if (wp == HOTKEY_ENGLISH) setMode(MODE_ENGLISH);
            return 0;
        case WM_DESTROY:
            Shell_NotifyIconW(NIM_DELETE, &g_nid);
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

// Load the dictionary + AiCMS aliases from the .exe's own folder (ASCII install path).
static void loadDictionary() {
    char exe[MAX_PATH]; DWORD n = GetModuleFileNameA(nullptr, exe, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return;
    std::string dir(exe, n);
    size_t slash = dir.find_last_of("\\/");
    dir = (slash == std::string::npos) ? std::string(".") : dir.substr(0, slash);
    if (g_db.loadFile(dir + "\\bangla-dictionary.txt") > 0) {
        g_db.loadAliases(dir + "\\hardwords_raw.tsv");
        g_dbReady = true;
    }
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, LPWSTR, int) {
    g_hInst = hInst;
    SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32);

    HANDLE once = CreateMutexW(nullptr, TRUE, L"BanglaKeyboardTraySingleton");
    if (once && GetLastError() == ERROR_ALREADY_EXISTS) {
        MessageBoxW(nullptr, L"বাঙলা কিবোর্ড is already running (see the tray).",
                    L"বাঙলা কিবোর্ড", MB_OK | MB_ICONINFORMATION);
        return 0;
    }

    loadDictionary();

    WNDCLASSW wc = {};
    wc.lpfnWndProc = wndProc; wc.hInstance = hInst; wc.lpszClassName = L"BanglaKeyboardTray";
    RegisterClassW(&wc);
    g_hWnd = CreateWindowW(wc.lpszClassName, L"বাঙলা কিবোর্ড", 0, 0, 0, 0, 0,
                           HWND_MESSAGE, nullptr, hInst, nullptr);

    // borderless, non-activating suggestion popup
    WNDCLASSW pc = {};
    pc.lpfnWndProc = popProc; pc.hInstance = hInst; pc.lpszClassName = L"BanglaKeyboardCand";
    pc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassW(&pc);
    g_pop = CreateWindowExW(WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
                            pc.lpszClassName, L"", WS_POPUP, 0, 0, 10, 10,
                            nullptr, nullptr, hInst, nullptr);
    g_popFont = CreateFontW(20, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET,
                            OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                            DEFAULT_PITCH, L"Nirmala UI");

    // বাংলা mode shows the real app logo; English shows a clear "E" off-indicator.
    const COLORREF white = RGB(255, 255, 255), black = RGB(0, 0, 0);
    int smIco = GetSystemMetrics(SM_CXSMICON);
    g_icoBn = loadLogoIcon(smIco);
    if (!g_icoBn) g_icoBn = LoadIconW(g_hInst, MAKEINTRESOURCEW(1));    // fallback to default size
    g_icoEn = makeIcon(L"E", white, black);
    HICON logo16 = loadLogoIcon(16);
    g_bmpBn = iconToMenuBitmap(logo16 ? logo16 : g_icoBn, 16);
    if (logo16) DestroyIcon(logo16);
    g_bmpEn = makeMenuBitmap(L"E", white, black);

    g_nid.cbSize = sizeof(g_nid);
    g_nid.hWnd   = g_hWnd;
    g_nid.uID    = 1;
    g_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_nid.uCallbackMessage = WM_TRAY;
    g_nid.hIcon  = g_icoEn;
    lstrcpynW(g_nid.szTip, modeTip(), ARRAYSIZE(g_nid.szTip));
    Shell_NotifyIconW(NIM_ADD, &g_nid);

    g_hook = SetWindowsHookExW(WH_KEYBOARD_LL, hookProc, hInst, 0);
    RegisterHotKey(g_hWnd, HOTKEY_BANGLA,  MOD_CONTROL | MOD_ALT, 'B');   // বাংলা
    RegisterHotKey(g_hWnd, HOTKEY_ENGLISH, MOD_CONTROL | MOD_ALT, 'E');   // English

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0)) { TranslateMessage(&msg); DispatchMessageW(&msg); }

    if (g_hook) UnhookWindowsHookEx(g_hook);
    UnregisterHotKey(g_hWnd, HOTKEY_BANGLA);
    UnregisterHotKey(g_hWnd, HOTKEY_ENGLISH);
    if (g_icoBn) DestroyIcon(g_icoBn);
    if (g_icoEn) DestroyIcon(g_icoEn);
    if (g_bmpBn) DeleteObject(g_bmpBn);
    if (g_bmpEn) DeleteObject(g_bmpEn);
    if (g_popFont) DeleteObject(g_popFont);
    if (once) { ReleaseMutex(once); CloseHandle(once); }
    return 0;
}
