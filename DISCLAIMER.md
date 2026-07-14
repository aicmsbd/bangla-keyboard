# Disclaimer

This is an **independent** project by **AiCMS.BD**
(<https://bangla.it.com>). It is **not affiliated with, endorsed by, or
connected to** any commercial Bangla keyboard or font vendor.

## Input method
The keyboard is a **phonetic ("Banglish") input method**: you type romanized
text (`amar` → আমার) and it becomes Bangla as you type, with live word
suggestions. All platforms share one phonetic engine (`engine/phonetic/`) with
the same transliteration rules and the same offline suggestion index
(a dictionary of about 35,000 words plus AiCMS.BD romanization aliases). This
project ships only:

- the shared C++ phonetic engine and its dictionary data (created by AiCMS.BD),
  and
- newly created icon artwork (AiCMS.BD — not taken from any other product).

Any product names or trademarks that may describe phonetic Bangla typing belong
to their respective owners. This project does **not** use, bundle, or
redistribute any third‑party vendor's proprietary software, branding, or fonts.

## Fonts
**No fonts are bundled or redistributed.** The keyboard emits standard Unicode,
so Bangla renders with any system Bangla font (modern macOS/Windows/Linux ship
Bengali support).

## Privacy
The keyboard makes **no network calls at all** — it never opens a socket. There
is no telemetry and there are no accounts; everything runs on‑device.

## No warranty
Provided "as is", without warranty of any kind. Use at your own risk. Licensed
under the AICMS Public License v1.0; see `LICENSE` and `NOTICE` for details.

If you are a rights holder and believe something here should be changed or
removed, please open an issue and it will be addressed promptly.
