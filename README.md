# kde-accent-key

Turn any key into a Spanish-style dead accent key on KDE Plasma (Wayland), like the ´ key on a Spanish keyboard:

| Press | Then | Result |
|---|---|---|
| key | a e i o u | á é í ó ú |
| Shift + key | u | ü |

## Usage

```bash
chmod +x setup-accent-key.sh
./setup-accent-key.sh
```

The script asks you to press the key you want to use (it needs sudo for this, because it reads the keyboard directly so it can see keys like Right Ctrl on their own). It then:

1. Writes a custom XKB symbols file, rules file and option registry under `~/.config/xkb`, backing up any existing files it didn't create.
2. Offers to enable the option for you via `kwriteconfig6`, keeping any keyboard options you already have (such as a Compose key). If you decline, enable it in **System Settings → Keyboard → Key Bindings → Custom options**.

Log out and back in afterwards.

If detection doesn't work, you can type the XKB key name instead, e.g. `RCTL` (Right Ctrl), `MENU` (Menu key), `RALT` (AltGr) or `BKSL` (# key).

## Undo

```bash
./setup-accent-key.sh --undo
```

Then log out and back in.

## Notes

- Wayland only: X11 sessions don't read `~/.config/xkb`.
- This doesn't give you ñ. Pair it with a Compose key (`Compose ~ n`).
- Choosing AltGr loses your AltGr characters. Choosing the # key offers to keep `#` and `~` on AltGr.
