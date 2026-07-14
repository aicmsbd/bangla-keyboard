// বাঙলা কিবোর্ড — Linux IBus engine (phonetic "Banglish", the twin of the macOS/Windows apps).
//
// Reuses the SHARED phonetic engine (../engine/phonetic, header-only): the in-progress roman
// buffer is transliterated Banglish -> Bangla and shown in the PREEDIT (underlined), while the
// offline dictionary + AiCMS aliases fill IBus's native candidate LOOKUP TABLE. Type "amar" ->
// আমার; press 1..6 (or ↑/↓ + space) to pick a suggested word. Same engine + dictionary as the
// other platforms, fully offline.
//
// IBus fits this cleanly: preedit for the live transliteration, a lookup table for suggestions,
// commit on a word boundary / selection / focus-out. Keys come in as US-QWERTY keyvals (the
// engine declares layout "us"), which already encode Shift — so the keyval IS the ASCII char.
//
// Build: see build.sh (g++ + `pkg-config --cflags --libs ibus-1.0`).
#include <ibus.h>
#include <string>
#include <vector>
#include <fstream>
#include <unistd.h>
#include "phonetic.hpp"
#include "worddb.hpp"

typedef struct _IBusBangla {
    IBusEngine parent;
    std::string* roman;                 // ASCII typed so far in the current word
    std::vector<std::u16string>* cands; // current suggestions (index -> word)
    IBusLookupTable* table;             // the visible candidate list
} IBusBangla;
typedef struct _IBusBanglaClass { IBusEngineClass parent; } IBusBanglaClass;

GType ibus_bangla_get_type(void);
#define IBUS_TYPE_BANGLA (ibus_bangla_get_type())
G_DEFINE_TYPE(IBusBangla, ibus_bangla, IBUS_TYPE_ENGINE)

static gchar* u16utf8(const std::u16string& s) {
    return g_utf16_to_utf8((const gunichar2*)s.data(), (glong)s.size(), nullptr, nullptr, nullptr);
}

// ---- offline dictionary (loaded once, shared by all engine instances) ------
static banglaphon::WordDB* g_db = nullptr;
static bool                g_dbReady = false;

static std::string exe_dir() {
    char buf[4096]; ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n <= 0) return "";
    buf[n] = 0; std::string p(buf); size_t s = p.find_last_of('/');
    return s == std::string::npos ? "" : p.substr(0, s);
}
// Find the folder holding bangla-dictionary.txt: $BANGLA_DICT_DIR, the system share dir, or next
// to the binary (standalone test / tarball).
static std::string find_data_dir() {
    std::vector<std::string> cands;
    if (const char* env = getenv("BANGLA_DICT_DIR")) if (*env) cands.push_back(env);
    cands.push_back("/usr/share/bangla-keyboard");
    std::string ed = exe_dir();
    if (!ed.empty()) { cands.push_back(ed); cands.push_back(ed + "/../share/bangla-keyboard"); }
    for (const auto& d : cands) { std::ifstream f(d + "/bangla-dictionary.txt"); if (f.good()) return d; }
    return "";
}
static void load_db_once() {
    if (g_db) return;
    g_db = new banglaphon::WordDB();
    std::string d = find_data_dir();
    if (!d.empty() && g_db->loadFile(d + "/bangla-dictionary.txt") > 0) {
        g_db->loadAliases(d + "/hardwords_raw.tsv");
        g_dbReady = true;
    }
}

// ---- preedit + candidate list ----------------------------------------------
static void hide_all(IBusBangla* self) {
    ibus_engine_hide_preedit_text((IBusEngine*)self);
    ibus_engine_hide_lookup_table((IBusEngine*)self);
}

// preedit = transliterate(roman) underlined; lookup table = dictionary suggestions for roman.
static void update_ui(IBusBangla* self) {
    if (self->roman->empty()) { hide_all(self); return; }
    std::u16string bn = banglaphon::transliterate(*self->roman);
    gchar* u8 = u16utf8(bn);
    glong len = g_utf8_strlen(u8, -1);
    IBusText* t = ibus_text_new_from_string(u8);
    ibus_text_append_attribute(t, IBUS_ATTR_TYPE_UNDERLINE, IBUS_ATTR_UNDERLINE_SINGLE, 0, (guint)len);
    ibus_engine_update_preedit_text((IBusEngine*)self, t, (guint)len, TRUE);
    g_free(u8);

    self->cands->clear();
    ibus_lookup_table_clear(self->table);
    if (g_dbReady) {
        for (const auto& w : g_db->lookup(*self->roman, 6)) {
            self->cands->push_back(w);
            gchar* wu8 = u16utf8(w);
            ibus_lookup_table_append_candidate(self->table, ibus_text_new_from_string(wu8));
            g_free(wu8);
        }
    }
    if (self->cands->empty()) ibus_engine_hide_lookup_table((IBusEngine*)self);
    else ibus_engine_update_lookup_table((IBusEngine*)self, self->table, TRUE);
}

static void commit_u16(IBusBangla* self, const std::u16string& s) {
    self->roman->clear();
    hide_all(self);
    if (!s.empty()) { gchar* u8 = u16utf8(s); ibus_engine_commit_text((IBusEngine*)self, ibus_text_new_from_string(u8)); g_free(u8); }
}
// Commit the transliteration as-is (word boundary), or a chosen suggestion.
static void commit_preedit(IBusBangla* self)      { if (!self->roman->empty()) commit_u16(self, banglaphon::transliterate(*self->roman)); }
static void commit_candidate(IBusBangla* self, guint i) { if (i < self->cands->size()) commit_u16(self, (*self->cands)[i]); }
static void cancel_run(IBusBangla* self)          { self->roman->clear(); hide_all(self); }

// The ASCII scheme char this US-QWERTY keyval would type, or 0 if it's a word boundary. Keyval
// already reflects Shift (S->ষ, s->স). Digits and ^ . ` are in-word, matching the engine.
static char phonetic_char(guint kv) {
    if ((kv >= 'a' && kv <= 'z') || (kv >= 'A' && kv <= 'Z') || (kv >= '0' && kv <= '9')) return (char)kv;
    if (kv == '^' || kv == '.' || kv == '`') return (char)kv;
    return 0;
}

static gboolean ibus_bangla_process_key_event(IBusEngine* engine, guint keyval, guint keycode, guint state) {
    IBusBangla* self = (IBusBangla*)engine;
    (void)keycode;
    if (state & IBUS_RELEASE_MASK) return FALSE;                 // key-up: ignore
    switch (keyval) {                                            // a lone modifier keeps the run
        case IBUS_KEY_Shift_L:   case IBUS_KEY_Shift_R:
        case IBUS_KEY_Control_L: case IBUS_KEY_Control_R:
        case IBUS_KEY_Alt_L:     case IBUS_KEY_Alt_R:
        case IBUS_KEY_Super_L:   case IBUS_KEY_Super_R:
        case IBUS_KEY_Meta_L:    case IBUS_KEY_Meta_R:
        case IBUS_KEY_Caps_Lock: case IBUS_KEY_Shift_Lock:
            return FALSE;
    }
    try {
        load_db_once();
        if (state & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_MOD4_MASK)) { commit_preedit(self); return FALSE; }
        bool have = !self->roman->empty();

        if (have) {
            switch (keyval) {
                case IBUS_KEY_Escape:    cancel_run(self);   return TRUE;
                case IBUS_KEY_Return:
                case IBUS_KEY_KP_Enter:  commit_preedit(self); return TRUE;   // commit translit, eat Enter
                case IBUS_KEY_space:     commit_preedit(self); return FALSE;  // commit, then insert the space
                case IBUS_KEY_BackSpace: self->roman->pop_back(); update_ui(self); return TRUE;
                case IBUS_KEY_Up:    case IBUS_KEY_KP_Up:
                    ibus_lookup_table_cursor_up(self->table);   ibus_engine_update_lookup_table((IBusEngine*)self, self->table, TRUE); return TRUE;
                case IBUS_KEY_Down:  case IBUS_KEY_KP_Down:
                    ibus_lookup_table_cursor_down(self->table); ibus_engine_update_lookup_table((IBusEngine*)self, self->table, TRUE); return TRUE;
                case IBUS_KEY_Page_Up:   ibus_lookup_table_page_up(self->table);   ibus_engine_update_lookup_table((IBusEngine*)self, self->table, TRUE); return TRUE;
                case IBUS_KEY_Page_Down: ibus_lookup_table_page_down(self->table); ibus_engine_update_lookup_table((IBusEngine*)self, self->table, TRUE); return TRUE;
            }
            // number key selects the Nth suggestion (standard IBus behaviour)
            if (keyval >= '1' && keyval <= '9') {
                guint idx = keyval - '1';
                if (idx < self->cands->size()) { commit_candidate(self, idx); return TRUE; }
            }
        }

        char c = phonetic_char(keyval);
        if (c) {
            if (self->roman->size() > 1024) commit_preedit(self);   // bound a stuck run
            self->roman->push_back(c);
            update_ui(self);
            return TRUE;
        }
        // any other key: finalise the current word, then let the key through
        if (have) commit_preedit(self);
        return FALSE;
    } catch (...) {                                             // never unwind into IBus's C dispatch
        if (self->roman) self->roman->clear();
        hide_all(self);
        return FALSE;
    }
}

static void ibus_bangla_focus_out(IBusEngine* e) { commit_preedit((IBusBangla*)e); IBUS_ENGINE_CLASS(ibus_bangla_parent_class)->focus_out(e); }
static void ibus_bangla_reset(IBusEngine* e)     { commit_preedit((IBusBangla*)e); IBUS_ENGINE_CLASS(ibus_bangla_parent_class)->reset(e); }
static void ibus_bangla_disable(IBusEngine* e)   { commit_preedit((IBusBangla*)e); IBUS_ENGINE_CLASS(ibus_bangla_parent_class)->disable(e); }

static void ibus_bangla_init(IBusBangla* self) {
    self->roman = new std::string();
    self->cands = new std::vector<std::u16string>();
    self->table = ibus_lookup_table_new(6, 0, TRUE, TRUE);      // page 6, cursor visible, round
    g_object_ref_sink(self->table);
}
static void ibus_bangla_finalize(GObject* obj) {
    IBusBangla* self = (IBusBangla*)obj;
    delete self->roman; self->roman = nullptr;
    delete self->cands; self->cands = nullptr;
    if (self->table) { g_object_unref(self->table); self->table = nullptr; }
    G_OBJECT_CLASS(ibus_bangla_parent_class)->finalize(obj);
}
static void ibus_bangla_class_init(IBusBanglaClass* klass) {
    G_OBJECT_CLASS(klass)->finalize = ibus_bangla_finalize;
    IBusEngineClass* ec = IBUS_ENGINE_CLASS(klass);
    ec->process_key_event = ibus_bangla_process_key_event;
    ec->focus_out = ibus_bangla_focus_out;
    ec->reset     = ibus_bangla_reset;
    ec->disable   = ibus_bangla_disable;
}

// ---- daemon entry point ----------------------------------------------------
static IBusBus* g_bus = nullptr;

int main(int argc, char** argv) {
    const char* xml = nullptr;     // standalone test: register a component from this XML first
    for (int i = 1; i < argc; ++i)
        if (g_strcmp0(argv[i], "--xml") == 0 && i + 1 < argc) xml = argv[++i];

    ibus_init();
    g_bus = ibus_bus_new();
    if (!ibus_bus_is_connected(g_bus)) { g_printerr("ibus-bangla: IBus daemon not running\n"); return 1; }
    g_object_ref_sink(g_bus);

    IBusFactory* factory = ibus_factory_new(ibus_bus_get_connection(g_bus));
    g_object_ref_sink(factory);
    ibus_factory_add_engine(factory, "bangla", IBUS_TYPE_BANGLA);

    if (xml) {   // standalone: teach the running daemon about our engine at runtime
        IBusComponent* comp = ibus_component_new_from_file(xml);
        if (comp) ibus_bus_register_component(g_bus, comp);
    }
    ibus_bus_request_name(g_bus, "org.freedesktop.IBus.Bangla", 0);

    ibus_main();
    return 0;
}
