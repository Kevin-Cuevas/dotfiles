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
| GRUB boot background `grub/backgrounds/nord.jpg` | `/boot/grub/themes/nord/boot-background.jpg` | same repo, base layer of `backgrounds/background.xcf` | `f2bf575` | GPLv3 |
| GRUB icon sets `color`, `whitesur` | `/boot/grub/themes/nord/icons` (when chosen) | same repo, `assets/assets-{color,whitesur}/icons-1080p` | `f2bf575` | GPLv3 |
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

## GRUB boot background

`GRUB_THEME` only styles the menu. Once an entry is picked, GRUB prints
`Loading Linux…` on its plain terminal, and that terminal's image (which stays
on screen until Plymouth takes over) is `GRUB_BACKGROUND`. When it's unset,
Debian's `/etc/grub.d/05_debian_theme` falls back to desktop-base's wallpaper
(`ceratopsian` on trixie/forky), so that second looked like a different theme.

`grub/backgrounds/nord.jpg` is the nord menu background **without** the menu
panel. The panel is baked into `background-nord.jpg`, but upstream's GIMP source
keeps the forest photo as its own layer. Outside the panel the two images match
(RMSE ≈ 0.3 %, JPEG noise). It's kept outside `themes/nord/` so that folder stays
byte-identical to upstream's build. `dev-boot` copies it into the theme as
`boot-background.jpg` and sets `GRUB_BACKGROUND` in its drop-in. It's
baseline JPEG, since GRUB's reader can't decode progressive files. To rebuild it:

```bash
magick 'backgrounds/background.xcf[0]' -strip -interlace none \
  -sampling-factor 4:2:0 -quality 90 nord.jpg
```

## GRUB icon sets

`nord/icons` is the **white** set. `grub/icons/color` and
`grub/icons/whitesur` are upstream's other two 1080p sets, copied as-is
(`assets/assets-color/icons-1080p`, `assets/assets-whitesur/icons-1080p`).
Upstream's `install.sh` only offers white; `dev-boot --grub-icons=<set>`
assembles the theme with the chosen set replacing `icons/`.

## Plymouth `cuts_alt`

Copied as-is from `pack_1/cuts_alt` (it already includes its `LICENSE`). The
`.plymouth`/`.script` files are stored as 644: they're data, not executables.

The other 79 themes of that repo are **not** vendored: `dev-boot` can install
any of them on a single machine, downloading only that theme's folder at the
same pinned commit (`PLY_UPSTREAM_COMMIT` in `dev-boot`; bump it together with
the commit above).
