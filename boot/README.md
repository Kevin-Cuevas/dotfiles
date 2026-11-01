# boot/

Boot themes, installed system-wide by `dev-boot` (bootstrap menu option 14).
Not a stow package: GRUB and Plymouth read them from root-owned paths.

Both are third-party GPLv3 themes, **vendored** (copied into this repo with
their `LICENSE`) instead of downloaded, so a fresh machine never depends on the
upstream repos still existing. They are byte-identical to upstream at the
commits below; to update one, rebuild/copy it from upstream, replace the
folder here, bump the commit in this file and run `dev-boot`.

| Theme | Installed to | Upstream | Commit | License |
| ----- | ------------ | -------- | ------ | ------- |
| GRUB `nord` | `/boot/grub/themes/nord` | [stevendejongnl/grub2-nord-theme](https://github.com/stevendejongnl/grub2-nord-theme) | `f2bf575` (2025-04-07) | GPLv3 |
| Plymouth `cuts_alt` | `/usr/share/plymouth/themes/cuts_alt` | [adi1090x/plymouth-themes](https://github.com/adi1090x/plymouth-themes) `pack_1/cuts_alt` | `5d88174` (2023-08-22) | GPLv3 |

## GRUB `nord`: how it was built

Upstream ships sources plus an `install.sh` that assembles one variant and then
edits `/etc/default/grub` with `sed` (which is why it is never run here). This
copy is the **1080p / white icons** variant, i.e. what `install.sh` produces
with those choices:

```bash
cp common/*.png common/*.pf2                 nord/
cp config/theme-1080p.txt                    nord/theme.txt
cp backgrounds/1080p/background-nord.jpg     nord/background.jpg
cp -r assets/assets-white/icons-1080p        nord/icons
cp assets/assets-select/select-1080p/*.png   nord/
cp assets/info-1080p.png                     nord/info.png
cp LICENSE                                   nord/
```

## Plymouth `cuts_alt`

Copied as-is from `pack_1/cuts_alt` (it already includes its `LICENSE`). The
`.plymouth`/`.script` files are stored as 644: they're data, not executables.
