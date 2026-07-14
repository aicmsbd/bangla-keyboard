// বাঙলা কিবোর্ড — Linux preview-panel window (WebKitGTK).
//
// Opens a native GTK window hosting a WebKitWebView that loads the SAME shared UI as the macOS
// and Windows apps (ui/index.html): type Banglish in the editor, get live suggestions, switch
// বাংলা/English, and copy the text. The UI is a self-contained web app (its own transliteration
// + offline dictionary in JS), so the panel needs no engine of its own — just the WebView.
//
// This is the editor-window companion to the system-wide IBus engine (they are independent).
//
// Build: cc panel.c $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1) -o bangla-panel
//        (webkit2gtk-4.0 also works on older distros — build.sh picks whichever is installed).
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <stdio.h>

// Locate ui/index.html: next to the binary (dev / tarball), else the system share dir (.deb).
static const char* find_index_html(void) {
    static char p[PATH_MAX];
    char exe[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n > 0) {
        exe[n] = 0;
        char* slash = strrchr(exe, '/');
        if (slash) {
            *slash = 0;
            snprintf(p, sizeof(p), "%s/ui/index.html", exe);
            if (access(p, R_OK) == 0) return p;
            snprintf(p, sizeof(p), "%s/../share/bangla-keyboard/ui/index.html", exe);
            if (access(p, R_OK) == 0) return p;
        }
    }
    const char* sys = "/usr/share/bangla-keyboard/ui/index.html";
    if (access(sys, R_OK) == 0) { snprintf(p, sizeof(p), "%s", sys); return p; }
    return NULL;
}

int main(int argc, char** argv) {
    gtk_init(&argc, &argv);

    GtkWidget* win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "বাঙলা কিবোর্ড");
    gtk_window_set_default_size(GTK_WINDOW(win), 600, 680);
    gtk_window_set_position(GTK_WINDOW(win), GTK_WIN_POS_CENTER);
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    // App icon (best-effort; ignored if the theme/file is unavailable).
    gtk_window_set_icon_from_file(GTK_WINDOW(win),
        "/usr/share/icons/hicolor/128x128/apps/bangla-keyboard.png", NULL);

    WebKitWebView* web = WEBKIT_WEB_VIEW(webkit_web_view_new());
    gtk_container_add(GTK_CONTAINER(win), GTK_WIDGET(web));

    const char* idx = find_index_html();
    if (idx) {
        char uri[PATH_MAX + 16];
        snprintf(uri, sizeof(uri), "file://%s", idx);
        webkit_web_view_load_uri(web, uri);
    } else {
        webkit_web_view_load_html(web,
            "<body style='font-family:sans-serif;padding:24px;color:#333'>"
            "<h2>বাঙলা কিবোর্ড</h2><p>UI files not found (ui/index.html).</p></body>", NULL);
    }

    gtk_widget_show_all(win);
    gtk_main();
    return 0;
}
