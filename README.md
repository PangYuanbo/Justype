# JustType

LLM-powered fuzzy keyboard input for macOS. Tap a trigger key, type in the
"naked" keyboard form (no IME, no autocorrect), and let an LLM turn it into
the text you actually meant — Chinese, Japanese, Korean, casing,
punctuation, all of it.

## How it works

1. Tap your trigger key (Right Option / Fn / Caps Lock) — a floating "magic
   box" appears at the bottom of the screen.
2. Type whatever you want, in raw keyboard form. Example: `wo yao chi fan`.
3. Pause briefly. The candidate (`我要吃饭`) appears below as IME-style
   suggestion.
4. Press `↩` to accept the candidate. It locks in. Keep typing more if you
   want.
5. Tap the trigger key again — the full text is injected into whatever app
   you were focused on.

`Esc` aborts the session without injecting. `Backspace` edits the current
raw segment.

## Install

Download `JustType.zip` from the [latest release](https://github.com/PangYuanbo/Justype/releases/latest),
unzip, drag `JustType.app` into `/Applications`, and launch.

On first run macOS will ask for **Accessibility** permission (required, so
JustType can listen for the trigger key) and optionally **Screen Recording**
(used to attach a small screenshot as context for the LLM — improves
accuracy in mixed-language situations).

After granting Accessibility, **fully quit and reopen the app** so the
permission takes effect.

## Configuration

Click the menu-bar keyboard icon → **LLM 设置** to configure:
- Base URL — any OpenAI-compatible endpoint (default: OpenRouter).
- API key — your own key. JustType ships with no default; you must provide
  one.
- Model — defaults to `google/gemini-2.5-flash`.

Trigger key, screen-context toggle, language (English / 中文), and history
are also in that menu.

## Build from source

```bash
git clone https://github.com/PangYuanbo/Justype.git
cd Justype
make run
```

Requires macOS 14+ and Swift 5.9+. The `Makefile` handles signing
(self-signed if no Apple cert is present), bundling, and launching.

```bash
make bundle    # build the .app
make install   # copy to /Applications
make clean
```

## License

MIT.
