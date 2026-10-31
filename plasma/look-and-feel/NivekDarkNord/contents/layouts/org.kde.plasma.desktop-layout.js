// Layout de escritorio + panel de NivekDarkNord/NivekLightNord (el mismo en
// ambos: el claro/oscuro solo cambia colores e iconos, no el panel). Solo se
// aplica si en System Settings se marca "Desktop and window layout" al aplicar
// el Global Theme, o con `dev-plasma --reset-layout`; el cambio automatico
// claro/oscuro nunca lo toca.
//
// Nada de rutas absolutas: el layout viaja en los dotfiles a otras maquinas.
//   - Wallpaper: Nord Flare (paquete con images/ + images_dark/, Plasma elige
//     la variante segun el esquema de color). La ruta se calcula con
//     userDataPath() en vez de /home/<usuario>/... fijo.
//   - Icono del lanzador: nombre de icono del tema (start-here-debian, viene en
//     Papirus) en vez de un .svg suelto en ~/Downloads que no existe en otra
//     maquina.
var nordFlare = "file://" + userDataPath("data", "wallpapers/Nord-flare/");

var plasma = getApiVersion(1);

var layout = {
    "desktops": [
        {
            "applets": [
            ],
            "config": {
                "/": {
                    "ItemGeometries-1920x1080": "",
                    "ItemGeometriesHorizontal": "",
                    "formfactor": "0",
                    "immutability": "1",
                    "lastScreen": "0",
                    "wallpaperplugin": "org.kde.image"
                },
                "/ConfigDialog": {
                    "DialogHeight": "630",
                    "DialogWidth": "810"
                },
                "/Wallpaper/org.kde.image/General": {
                    "Image": nordFlare
                }
            },
            "wallpaperPlugin": "org.kde.image"
        }
    ],
    "panels": [
        {
            "alignment": "center",
            "applets": [
                {
                    "config": {
                        "/": {
                            "popupHeight": "509",
                            "popupWidth": "647"
                        },
                        "/ConfigDialog": {
                            "DialogHeight": "630",
                            "DialogWidth": "810"
                        },
                        "/General": {
                            "favoritesPortedToKAstats": "true",
                            "icon": "start-here-debian",
                            "systemFavorites": "suspend\\,hibernate\\,reboot\\,shutdown"
                        }
                    },
                    "plugin": "org.kde.plasma.kickoff"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.pager"
                },
                {
                    "config": {
                        "/General": {
                            "launchers": "applications:systemsettings.desktop,preferred://filemanager,applications:kitty.desktop,applications:firefox-dev.desktop"
                        }
                    },
                    "plugin": "org.kde.plasma.icontasks"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.marginsseparator"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.systemtray"
                },
                {
                    "config": {
                        "/": {
                            "popupHeight": "451",
                            "popupWidth": "560"
                        },
                        "/Appearance": {
                            "fontWeight": "400"
                        }
                    },
                    "plugin": "org.kde.plasma.digitalclock"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.showdesktop"
                }
            ],
            "config": {
                "/": {
                    "formfactor": "2",
                    "immutability": "1",
                    "lastScreen": "0",
                    "wallpaperplugin": "org.kde.image"
                }
            },
            "height": 2.5555555555555554,
            "hiding": "normal",
            "lengthMode": "fill",
            "location": "bottom",
            "maximumLength": 106.66666666666667,
            "minimumLength": 106.66666666666667,
            "offset": 0,
            "opacity": "adaptive"
        }
    ],
    "serializationFormatVersion": "1"
}
;

plasma.loadSerializedLayout(layout);
