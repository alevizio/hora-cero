# Hora Cero · Invasión Buenos Aires

*English below.*

Buenos Aires, 1958, la noche en que empieza a nevar. Una nieve que mata a quien toca.

**Jugalo gratis en el navegador: [horacero.app](https://horacero.app).** ¿Encontraste un error o se te ocurrió algo?
[Contalo acá](https://github.com/alevizio/hora-cero/issues/new/choose).

**Hora Cero** es un juego de sigilo y táctica en tiempo real, visto desde arriba, hecho con [Godot 4.7](https://godotengine.org).
Manejás a un grupo de cuatro vecinos (Hornero, Lechuza, Benteveo y Biguá), cada uno con lo suyo: tocás a uno para
elegir quién actúa y tocás el piso para moverlo. Este repositorio tiene el **adelanto** del juego, dos niveles:

1. **Plaza de Mayo.** La noche en que empieza la nevada, con Juan Salvo y los cuatro vecinos: hay que llevar a la
   gente que queda en la plaza bajo techo (el pórtico de la Catedral, la recova del Cabildo, el subte, el tranvía, el
   colectivo) antes de que la nieve la tape, mirando las olas y aprovechando las calmas.
2. **Riachuelo.** La Boca, esa misma noche de invierno (una historia original): estudiar las patrullas, los faroles
   del muelle y el reflector de la lancha, sacar al pasajero del sótano del café La Bruma y cruzarlo al otro lado del
   Riachuelo.

El juego arranca en castellano (rioplatense) y se pasa al inglés con las teclas ES / EN de la pantalla de inicio (o
desde Configuración). Se juega con el dedo en el teléfono o con el mouse, en el navegador o en la compu.

El juego está inspirado en ***El Eternauta***, la historieta de **Héctor Germán Oesterheld** (guion) y **Francisco
Solano López** (dibujo), publicada por primera vez en *Hora Cero Semanal* (1957–1959), y se hizo con el permiso de sus
derechohabientes. Los personajes, las criaturas y los elementos de la historieta **no** están bajo las licencias
libres de este repositorio: fijate en [NOTICE](NOTICE).

¿Cómo se hizo? Los personajes, los niveles, la nieve, las voces y el trabajo con una IA, en
[docs/COMO_SE_HIZO.md](docs/COMO_SE_HIZO.md). Kit de diseño en Figma: [Hora Cero · kit](https://www.figma.com/design/Y03Bhe1LF6GyW3VJMOYqZN) (exportado en PNG en [docs/design/](docs/design/)).

## Abrirlo y jugarlo en Godot 4.7

1. Bajate [Godot 4.7](https://godotengine.org/download) (la versión estándar alcanza; no hace falta la de .NET).
2. En el administrador de proyectos tocá **Importar** y elegí `godot/project.godot`.
3. Apretá **F5** (Ejecutar proyecto). Arranca la pantalla de inicio y, después, la Plaza de Mayo.

Desde la terminal:

```sh
godot --path godot            # el juego
godot --path godot -e         # el editor
```

El proyecto usa el renderizador **Compatibility** (OpenGL 3 / WebGL 2), así que anda en máquinas modestas y en el
navegador. Cuando lo corrés desde el editor están abiertos los dos niveles; en un juego exportado el Riachuelo se abre
al ganar la Plaza. Algunas variables de entorno sirven para probar:

| Variable | Qué hace |
| --- | --- |
| `HORACERO_MISSION=plaza` o `riachuelo` | arranca en ese nivel |
| `HORACERO_UNLOCK=1` (o `0`) | abre todos los niveles (o los deja cerrados) en una build de depuración |
| `HORACERO_LANG=es` o `en` | fuerza el idioma |
| `HORACERO_INK=1` (o `0`) | dibuja el juego en tinta de historieta (o no) |
| `HORACERO_TITLE=1` | muestra la pantalla de inicio también en los tests |

### Tests

Los tests corren sin ventana. Desde la raíz del repositorio, con `GODOT` apuntando al binario de Godot 4.7:

```sh
GODOT=/ruta/a/Godot_v4.7-stable_linux.x86_64 tools/run_tests.sh               # importa y corre los 14
GODOT=/ruta/a/Godot_v4.7-stable_linux.x86_64 tools/run_tests.sh plaza_rules   # uno solo
```

O de a uno: `godot --headless --path godot --script res://tests/plaza_rules.gd`. La lista completa, y qué mira cada
uno, está en [docs/GAMEPLAY_API.md](docs/GAMEPLAY_API.md) (sección 18).

## La versión web

Necesitás las **plantillas de exportación** de Godot 4.7 (en el editor: Editor → Administrar plantillas de exportación)
y Python 3:

```sh
GODOT=/ruta/a/Godot_v4.7-stable_linux.x86_64 python3 tools/web_site_build.py /tmp/horacero-web
python3 -m http.server -d /tmp/horacero-web 8000      # y abrí http://localhost:8000
```

`tools/web_site_build.py` exporta el preset **Web**, le pone a la página (`godot/web/shell.html`) el título, la
descripción y las etiquetas para las vistas previas de los links (con `tools/site/og.jpg`), y corta el paquete en partes
de 48 MB como mucho, para que entre en un sitio publicado desde un repositorio de Git. La carpeta que deja se sube
tal cual a la raíz del sitio (https://horacero.app/ salvo que le pases `--site`). La exportación no usa hilos, así que
no hacen falta encabezados especiales (COOP/COEP) en el servidor. Opciones:

- `--ink`: arranca dibujado en tinta de historieta.
- `--site https://ejemplo.org/`: adónde apuntan las vistas previas de los links.
- `--feedback-url https://...` (y `--feedback-header "Nombre: valor"`, repetible): prende las preguntas de la
  pantalla de inicio y manda las respuestas a esa dirección como un objeto JSON (`godot/scripts/feedback.gd`). Sin
  esta opción **el juego no pregunta nada ni manda nada a ningún lado**. La dirección queda solo en la página de esa
  build, nunca en el repositorio.

Los tráilers y las imágenes para redes también salen del juego: `tools/trailer/horacero_*` filma tomas jugando de
verdad y arma los cortes con música sintetizada, y `tools/social/horacero/` compone las imágenes
([tools/social/README.md](tools/social/README.md) dice cómo).

## El arte con licencia

Los modelos 3D de **Juan Salvo** (con sus texturas y su retrato del HUD) y del **cascarudo** (con su copia liviana para
cuando la cámara está lejos), lo que se hizo para el juego a partir de ellos (el esqueleto de las patas del cascarudo y
el ícono del juego, que es un render del cascarudo), y los **vehículos** de la Plaza de Mayo (el colectivo de la línea
60 con su letrero, dos autos de la época del Retro Vehicle Pack con el generador del pack, y seis autos de los años
cuarenta y cincuenta hechos para Hora Cero con ese generador) son de **Santiago Siri**, y están en este repositorio
**con su permiso, para usar con Hora Cero**. **No están bajo la licencia MIT ni bajo CC BY 4.0**: sus autores se
reservan todos los derechos. No los uses fuera de Hora Cero sin pedir permiso. Juan Salvo y los cascarudos, además, son
personajes de la historieta, que se usan con el permiso de sus derechohabientes.

Están en:

- `godot/art_pack/juan_suit/` y `godot/art_pack/cascarudo/` (los slots `juan_suit` y `cascarudo` de
  `godot/art_pack/manifest.json`), y `art/juan_salvo/` (el fusil que lleva Juan Salvo);
- `godot/icon.png` (el ícono);
- `godot/assets/vehicles/` (los modelos listos para el juego, que hace `tools/vehicles.gd`) y `art/vehicles/` (los
  modelos tal como llegaron y los generadores).

Cada carpeta tiene su `CREDITS.txt`.

**Sin ese arte el juego se juega igual.** Si querés armar una versión sin él (para publicar la tuya, por ejemplo), borrá
esas carpetas, cambiá el ícono por uno tuyo y vaciá en el manifiesto el `file`, `portrait` y `lod` de los dos slots:
Juan Salvo pasa a ser un maniquí gris neutro y el cascarudo un bloque gris, cada uno con un cartel de LICENSED ART
PENDING, y en la plaza aparecen el colectivo y los autos propios del kit, sin marcas (`PlazaCity.has_vehicle()`). Los
créditos lo dicen, y los tests miran los reemplazos en vez de los modelos.

Para rehacer los vehículos desde las fuentes: `python3 art/vehicles/source/build_vehicles_1950s.py` (los seis autos de
la época, con NumPy) y después `godot --headless --path godot --script ../tools/vehicles.gd`. Juan Salvo sale de su
modelo original con `python3 tools/juan_suit.py <su .glb>` (el original no está en el repositorio), y el esqueleto del
cascarudo se lo pone `python3 tools/art_pack.py rig-creature`. [docs/ART_PACK.md](docs/ART_PACK.md) explica el paquete
de arte entero: cómo sumar figuras, recortes y modelos nuevos.

## Licencias

- **Código** (GDScript, shaders, escenas, la página web, las herramientas de `tools/` y la documentación): licencia MIT,
  en [LICENSE](LICENSE).
- **Los assets propios del juego** (texturas, interfaz, sonidos, figuras, voces sintéticas, retratos de los vecinos,
  íconos, datos de los niveles): Creative Commons Atribución 4.0 (CC BY 4.0), en [LICENSE-ASSETS](LICENSE-ASSETS),
  **salvo los elementos de la historieta**.
- **La historieta** (Juan Salvo, los cascarudos, la nevada mortal y lo demás que viene de ella) no está bajo ninguna de
  las dos licencias: se usa con el permiso de sus derechohabientes y este repositorio no da ningún derecho sobre ella.
- **Los modelos de Santiago Siri** (Juan Salvo, el cascarudo, el ícono, los vehículos y sus generadores de
  `art/vehicles/source/`: ver arriba) tampoco: todos los derechos reservados por sus autores, acá con su permiso solo para usar con Hora Cero.
- Las tipografías van con sus licencias (SIL OFL 1.1 y Apache 2.0) en `godot/assets/fonts/`.

El detalle, con el origen de cada cosa, está en [NOTICE](NOTICE).

## Créditos

- Juego: **Alejandro Vizio**.
- Inspirado en ***El Eternauta***, la historieta de **Héctor Germán Oesterheld** y **Francisco Solano López** (*Hora Cero
  Semanal*, Editorial Frontera, 1957–1959), con el permiso de sus derechohabientes.
- Modelos de Juan Salvo, del cascarudo y de los vehículos: **Santiago Siri**.
- Gracias a **Agustín Linenberg**, por el apoyo.
- La jugabilidad está basada en [Saboteurs](https://saboteurs.app), el otro juego de Alejandro Vizio.
- Motor: [Godot Engine](https://godotengine.org) (MIT).
- Figuras de la gente: horneadas a partir de los assets CC0 de [MakeHuman](http://www.makehumancommunity.org).
- Voces sintéticas: Qwen3-TTS (Qwen, Alibaba Cloud) y Kokoro-82M, ambos Apache 2.0; ninguna voz de una persona real.
- Tipografías: Barlow Condensed y Big Shoulders Stencil Display (SIL OFL 1.1), Special Elite (Apache 2.0).

## Cómo contribuir

¿Encontraste un error o tenés una idea? Abrí un [issue](https://github.com/alevizio/hora-cero/issues/new/choose): hay una plantilla para reportar un error y otra
para proponer algo. ¡Bienvenidos también los pull requests! Para que entren:

- Corré `tools/run_tests.sh` y que pasen todos. Si cambiás reglas, sumá o ajustá los checks del test que corresponde.
- El texto del juego se escribe en inglés en el código y en los datos, y su traducción va en `godot/locale/es.json`,
  en castellano rioplatense (con voseo). `python3 tools/i18n_extract.py --check` te dice si falta algo.
- Las texturas, los sonidos y los niveles salen de los scripts de `tools/` (por ejemplo `tools/gen_plaza_textures.py`,
  `tools/gen_audio.py`, `tools/dev/plaza_layout.py`): cambiá el script y regenerá, en vez de editar el archivo que sale.
- Arte nuevo solo con una licencia que permita redistribuirlo (lo ideal: hecho por vos, bajo CC BY 4.0) y con su
  crédito en el manifiesto. Los modelos de Santiago Siri no se tocan sin su permiso.
- Nada de claves, tokens ni direcciones de servicios en el repositorio: lo que haga falta se pasa al armar la build.
- [docs/GAMEPLAY_API.md](docs/GAMEPLAY_API.md) describe las reglas, los datos de los niveles y la capa 3D.

---

# Hora Cero · Invasión Buenos Aires (English)

Buenos Aires, 1958, the night it starts to snow. A snow that kills whoever it touches.

**Play it free in your browser: [horacero.app](https://horacero.app).** Found a bug, or have an idea?
[Tell us here](https://github.com/alevizio/hora-cero/issues/new/choose).

**Hora Cero** is a top-down, real-time stealth and tactics game made with [Godot 4.7](https://godotengine.org). You
lead a squad of four neighbours (Hornero, Lechuza, Benteveo and Biguá), each with his own skills: tap one to choose who
acts, tap the ground to move him. This repository holds the game's **preview**, two levels:

1. **Plaza de Mayo.** The night the snowfall begins, with Juan Salvo and the four neighbours: bring the people left in
   the square in under cover (the Catedral's portico, the Cabildo's arcade, the subte, the tram, the colectivo) before
   the snow covers them, watching the waves and using the lulls.
2. **Riachuelo.** La Boca, the same winter night (an original story): study the patrols, the quay's lamps and the
   launch's searchlight, bring the passenger up from the cellar of the café La Bruma and get him across the Riachuelo.

The game starts in (River Plate) Spanish and switches to English with the ES / EN keys on the launch screen (or in
Settings). It plays by touch on a phone or with a mouse, in the browser or on a computer.

It is inspired by ***El Eternauta***, the comic by **Héctor Germán Oesterheld** (script) and **Francisco Solano López**
(art), first published in *Hora Cero Semanal* (1957–1959), and made with the permission of its rights holders. The comic's characters,
creatures and story elements are **not** under this repository's free licences: see [NOTICE](NOTICE).

How was it made? The characters, the levels, the snow, the voices and working with an AI, in
[docs/HOW_IT_WAS_MADE.md](docs/HOW_IT_WAS_MADE.md). Figma design kit: [Hora Cero · kit](https://www.figma.com/design/Y03Bhe1LF6GyW3VJMOYqZN) (exported as PNGs in [docs/design/](docs/design/)).

## Open and run it in Godot 4.7

1. Get [Godot 4.7](https://godotengine.org/download) (the standard build; .NET is not needed).
2. In the project manager, choose **Import** and pick `godot/project.godot`.
3. Press **F5** (Run Project): the launch screen, then the Plaza de Mayo.

From a terminal: `godot --path godot` (the game) or `godot --path godot -e` (the editor). The project uses the
**Compatibility** renderer (OpenGL 3 / WebGL 2). Run from the editor, both levels are open; in an exported game the
Riachuelo opens when the Plaza is won. For testing: `HORACERO_MISSION=plaza|riachuelo` starts in that level,
`HORACERO_UNLOCK=1|0` opens every level (or keeps them locked) in a debug build, `HORACERO_LANG=es|en` forces the
language, `HORACERO_INK=1|0` turns comic-ink drawing on or off, `HORACERO_TITLE=1` shows the launch screen in tests too.

**Tests** run headless. From the repository root, with `GODOT` set to the Godot 4.7 binary:
`tools/run_tests.sh` imports the project and runs all 14 suites (or only those named:
`tools/run_tests.sh plaza_rules`). One by one: `godot --headless --path godot --script res://tests/plaza_rules.gd`.
[docs/GAMEPLAY_API.md](docs/GAMEPLAY_API.md), section 18, lists them and what each checks.

## Build the web version

With Godot 4.7's **export templates** installed (Editor → Manage Export Templates) and Python 3:

```sh
GODOT=/path/to/Godot_v4.7-stable_linux.x86_64 python3 tools/web_site_build.py /tmp/horacero-web
python3 -m http.server -d /tmp/horacero-web 8000      # then open http://localhost:8000
```

The script exports the **Web** preset, gives the page (`godot/web/shell.html`) its title, description and link-preview
tags (with `tools/site/og.jpg`), and cuts the pack into parts of at most 48 MB so it fits a site deployed from a Git
repository. Upload the folder as it is to the site's root (https://horacero.app/ unless `--site` says otherwise). The
export uses no threads, so the server needs no special (COOP/COEP) headers. Options: `--ink` (comic ink from the
start), `--site URL`, and `--feedback-url URL` (with `--feedback-header "Name: value"`, repeatable), which turns on the
launch screen's questions and posts the answers there as one JSON object (`godot/scripts/feedback.gd`). Without it
**the game asks nothing and sends nothing anywhere**; the address goes into that build's page only, never into the
repository.

The trailers and social images come out of the game too: `tools/trailer/horacero_*` films takes of real play and cuts
them to a synthesised score, and `tools/social/horacero/` lays out the images ([tools/social/README.md](tools/social/README.md)
says how).

## The licensed art

The 3D models of **Juan Salvo** (with his textures and HUD portrait) and of the **cascarudo** (with its lighter copy for
far views), what was made for the game from them (the cascarudo's leg rig, and the game's icon, a render of the
cascarudo), and the Plaza de Mayo's **vehicles** (the Línea 60 colectivo with its lettering, two cars of the time from
the Retro Vehicle Pack with the pack's generator, and six cars of the 1940s and 50s made for Hora Cero on that
generator) are by **Santiago Siri**, and are in this repository **with permission, for use with Hora Cero**. **They are
not under the MIT licence or CC BY 4.0**: all rights are reserved by their authors. Do not use them outside Hora Cero
without asking. Juan Salvo and the cascarudos are, besides, characters of the comic, used with its rights holders'
permission.

They are in:

- `godot/art_pack/juan_suit/` and `godot/art_pack/cascarudo/` (the `juan_suit` and `cascarudo` slots of
  `godot/art_pack/manifest.json`), and `art/juan_salvo/` (the rifle Juan Salvo carries);
- `godot/icon.png` (the icon);
- `godot/assets/vehicles/` (the game-ready meshes, made by `tools/vehicles.gd`) and `art/vehicles/` (the models as
  delivered, and the generators).

Each folder has its `CREDITS.txt`.

**The game plays the same without that art.** To make a build without it (to publish your own, say), delete those
folders, replace the icon with your own and empty the two slots' `file`, `portrait` and `lod` in the manifest: Juan
Salvo becomes a neutral grey mannequin and the cascarudo a grey block, each with a LICENSED ART PENDING plate, and the
square gets the level kit's own unbranded colectivo and cars (`PlazaCity.has_vehicle()`). The credits say so, and the
tests check the stand-ins instead of the models.

To rebuild the vehicles from their sources: `python3 art/vehicles/source/build_vehicles_1950s.py` (the six cars of
the time, with NumPy), then `godot --headless --path godot --script ../tools/vehicles.gd`. Juan Salvo is made from his
original model by `python3 tools/juan_suit.py <its .glb>` (the original is not in the repository), and the cascarudo's
skeleton is added by `python3 tools/art_pack.py rig-creature`. [docs/ART_PACK.md](docs/ART_PACK.md) explains the whole
art pack: how to add new figures, cut-outs and models.

## Licences

- **Code** (GDScript, shaders, scenes, the web page, the tools in `tools/`, the documentation): MIT, in [LICENSE](LICENSE).
- **The game's own assets** (textures, interface, sounds, figures, synthetic voices, the neighbours' portraits, icons,
  level data): Creative Commons Attribution 4.0 (CC BY 4.0), in [LICENSE-ASSETS](LICENSE-ASSETS), **except the comic's
  elements**.
- **The comic** (Juan Salvo, the cascarudos, the deadly snowfall and the rest of what comes from it) is under neither
  licence: it is used with its rights holders' permission and this repository grants no right to it.
- **Santiago Siri's models** (Juan Salvo, the cascarudo, the icon, the vehicles and their generators in
  `art/vehicles/source/`: see above) are under neither either: all rights reserved by their authors, here with their permission for use with Hora
  Cero only.
- The fonts keep their own licences (SIL OFL 1.1, Apache 2.0), in `godot/assets/fonts/`.

[NOTICE](NOTICE) has the details: where everything comes from.

## Credits

- Game: **Alejandro Vizio**.
- Inspired by ***El Eternauta***, the comic by **Héctor Germán Oesterheld** and **Francisco Solano López** (*Hora Cero
  Semanal*, Editorial Frontera, 1957–1959), with the permission of its rights holders.
- Models of Juan Salvo, the cascarudo and the vehicles: **Santiago Siri**.
- Thanks to **Agustín Linenberg**, for the support.
- The gameplay is based on [Saboteurs](https://saboteurs.app), Alejandro Vizio's other game.
- Engine: [Godot Engine](https://godotengine.org) (MIT).
- People's figures: baked from [MakeHuman](http://www.makehumancommunity.org)'s CC0 assets.
- Synthetic voices: Qwen3-TTS (Qwen, Alibaba Cloud) and Kokoro-82M, both Apache 2.0; no real person's voice.
- Fonts: Barlow Condensed and Big Shoulders Stencil Display (SIL OFL 1.1), Special Elite (Apache 2.0).

## Contributing

Found a bug or have an idea? Open an [issue](https://github.com/alevizio/hora-cero/issues/new/choose): there is a template for a bug report and one for an idea.
Pull requests are welcome too. To get one in:

- Run `tools/run_tests.sh` and make every suite pass; if you change a rule, add or adjust the checks in its suite.
- The game's text is written in English in the code and the data; its Spanish goes in `godot/locale/es.json`, in River
  Plate Spanish (with voseo). `python3 tools/i18n_extract.py --check` tells you what is missing.
- Textures, sounds and level layouts come out of the scripts in `tools/` (`tools/gen_plaza_textures.py`,
  `tools/gen_audio.py`, `tools/dev/plaza_layout.py`, ...): change the script and regenerate, rather than editing its output.
- New art only under a licence that allows redistributing it (best: your own work, under CC BY 4.0), with its credit in
  the manifest. Santiago Siri's models are not to be changed without permission.
- No keys, tokens or service addresses in the repository: whatever a build needs is passed when it is built.
- [docs/GAMEPLAY_API.md](docs/GAMEPLAY_API.md) describes the rules, the level data and the 3D layer.
