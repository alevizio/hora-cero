# El paquete de arte (art pack) y el modo historieta

En castellano; al final hay un resumen en inglés.

El juego puede mostrar personajes, criaturas y objetos hechos por otras personas (o por vos) **con permiso**: dibujos
planos que aparecen como **figuras de papel recortado** paradas en el mundo 3D, o modelos 3D. Todo eso vive en una
carpeta, `godot/art_pack/`, con un archivo que lo describe, `godot/art_pack/manifest.json`. Lo que todavía no llegó se
ve como una **figura neutra**: un maniquí gris liso (o un bloque gris, si no es una persona) con un cartel que dice
**ARTE LICENCIADO PENDIENTE** y el nombre del personaje. El maniquí no sugiere ningún traje, máscara, visor ni forma de
criatura: es a propósito.

Además del arte de la historieta que se describe abajo, en la carpeta hay dibujos de prueba neutros (un hombre con
sobretodo y gorra, una mancha redonda) hechos por código (`tools/art_pack.py test-art`) y modelos de prueba neutros
(una cápsula, un bloque, un poste articulado; `tools/art_pack.py test-models`).

Los dos personajes de la historieta que aparecen en la Plaza de Mayo son modelos con licencia de Santiago Siri, con su
permiso y el de los titulares de los derechos. **Están en el repositorio con su permiso,
para usar con Hora Cero, pero no bajo sus licencias libres**: no son MIT ni CC BY, sus autores se reservan todos los
derechos (cada carpeta tiene su `CREDITS.txt`, y el `NOTICE` lo explica). Lo mismo vale para lo que se hizo con ellos
(el modelo original de Juan Salvo y sus retratos en `art/juan_salvo/`, el ícono del juego, que es un render del
cascarudo) y para los vehículos de la plaza (`godot/assets/vehicles/`, `art/vehicles/`).

- **`juan_salvo`**: `juan_salvo/juan_salvo.glb` (1,80 m, esqueleto de Mixamo de 61 huesos con dedos, clips Idle, Walk,
  Run y Jump, el fusil como pieza aparte, «Rifle»). Desde el 20 de octubre de 2026 es el sobreviviente de traje azul
  de Santiago Siri: un bípedo hecho con Meshy AI (10.390 triángulos, una sola malla con texturas de
  2K: color, normales y metal-aspereza), capucha y traje azules, visor, respirador, mochila y cinto con cartucheras. Su
  paquete original queda fuera del repositorio; el del juego lo hace `python3 tools/juan_suit.py <su .glb>`: pasa sus
  huesos a metros con Y arriba (venía envuelto en un giro desde Z arriba y dos escalas), le da un reposo de pie con el
  fusil cruzado en las dos manos como lo llevaba el Juan anterior (el suyo era un cuadro de su caminata, con un pie en
  el aire; la piel queda atada como vino), le pone el fusil del Juan anterior (`art/juan_salvo/source/rifle.glb`) en
  un hueso propio bajo el pecho, junta sus vértices repetidos, deja solo los clips que usa el juego y baja las normales
  a 1024 y el metal-aspereza a 512 (el color queda en 2048: es un solo atlas para toda la figura, con la cara). La
  manera de agarrar el fusil y los dedos salen de su clip RunShoot, que empuña uno, y los clips no le mueven los dedos.
  Sus clips se hicieron a 1,46 m/s (caminar) y 5,21 m/s (correr), medidos del pie apoyado (`clip_speed`). Se viste con
  el acabado `pbr`. Su retrato del HUD, `juan_salvo/portrait.png` (768 × 768), está **renderizado en el motor
  a partir del modelo** y pintado encima en la serie de los vecinos (`tools/dev/salvo_portrait.gd -- <salida.png>
  juan_salvo 768 p1`, que corre `tools/dev/salvo_portrait_paint.py`). El Juan anterior, el **Blue Hood Survivor v4** que hizo Ale con Codex a
  partir de fotos de una figura de un amigo artista, queda en la carpeta de Ale y lo vuelve a hacer
  `tools/juan_blue_hood.py`; el primero (que refinaba `refine-person`, `tools/person_refine.py`) ya no está
  en este repositorio.
- **`survivor_hood`**: `survivor_hood/survivor_hood.glb` (1,80 m): el Blue Hood Survivor de Ale, hecho con
  `tools/juan_blue_hood.py <su .glb> godot/art_pack/survivor_hood/survivor_hood.glb`, con los mismos clips. Desde el
  21 de octubre de 2026 es la figura del vecino que agarra la capucha y la máscara del camión de Yrigoyen (el equipo
  de la Plaza, `gear[].look` en `plaza.json`): el juego lo viste con ella como si fuera un uniforme.
- **`cascarudo`**: `cascarudo/cascarudo.glb` (45.000 triángulos, la escultura de Santiago Siri con la forma intacta y un
  esqueleto en las patas que le pone `tools/art_pack.py rig-creature`: ver la sección 5) y una copia más liviana,
  `cascarudo/cascarudo_lod.glb` (13.499 triángulos, rebajada y con el mismo esqueleto), que el juego dibuja cuando la
  cámara está lejos. En el juego mide 4 m de largo (3,27 de alto, 3,53 de ancho).

Los modelos de Juan Salvo y del cascarudo (y los vehículos de la plaza) son de Santiago Siri: su nombre está en
`credit.author` de cada slot y en su `CREDITS.txt`. Si alguien quiere el juego sin ellos (para publicar una versión
propia, por ejemplo), borra esas carpetas y vacía `file`, `portrait` y `lod` de los dos slots: el juego muestra el
maniquí y el bloque gris con su cartel, y se juega igual. Sin los vehículos, la plaza usa el colectivo y los autos
propios del kit.

## 1. Cómo dibujar una figura en Figma

**Lienzo.** Un frame vertical. Para una persona: **1024 × 2048 px** (o el ancho que necesite la pose, con el alto en
2048). La figura de pie ocupa casi todo el alto: dejá unos 8 a 16 px de aire arriba y a los costados, y **los pies
apoyados en el borde de abajo** (el juego para la figura sobre lo más bajo que está dibujado, así que si sobra
lienzo abajo, flota). El juego recorta solo los márgenes transparentes, pero cuanto más justo el lienzo, mejor.

**Pose.** De pie, de **tres cuartos, mirando hacia la derecha**. Cuando el personaje camina hacia la izquierda de la
pantalla, el juego espeja el dibujo. Si el dibujo mira de frente, poné `"faces": "front"`; si mira a la izquierda,
`"faces": "left"`. Separá un poco los brazos del cuerpo y las piernas entre sí: el contorno de tinta que agrega el
juego rellena los huecos chicos.

**Fondo transparente.** Nada de rectángulo de fondo. Exportá en **PNG** (Export → PNG, 1x) con el fondo transparente.
Dentro de la figura, todo opaco: el recorte se queda con lo que es más de 50 % opaco, así que las sombras suaves o los
brillos semitransparentes adentro de la figura se pierden.

**Trazo y tintas.** En el juego una figura mide entre 60 y 200 píxeles de alto en pantalla. Para que el dibujo se
lea a ese tamaño:

- contorno exterior de alrededor del **1 % del alto** (unos **18 a 20 px** en un lienzo de 2048), en negro (#111);
- líneas interiores de la mitad (**8 a 10 px**);
- rellenos planos y pocos: blanco, dos o tres grises, negro. Las sombras, en negro lleno o con un rayado grueso (líneas
  de 10 px separadas por 20 px o más): las tramas finas hacen moaré al achicarse;
- nada de detalles más finos que unos 6 px: desaparecen.

Ese trazo es el que mejor combina con el **modo historieta** (sección 8), que dibuja el mundo con tinta negra y
contornos de unos 2 px de pantalla. El juego además le pone a cada figura un **contorno de tinta grueso** y un borde
fino de papel blanco, como un recorte: no hace falta dibujarlos.

**Vistas opcionales** (en archivos aparte, mismo estilo y escala):

| Vista | Archivo (sugerido) | Cómo |
|---|---|---|
| frente (obligatoria) | `juan_frente.png` | de pie, tres cuartos, mirando a la derecha |
| espalda | `juan_espalda.png` | de pie, de espaldas; se usa cuando camina alejándose de la cámara |
| agachado | `juan_agachado.png` | agachado, avanzando sigiloso; se muestra al 72 % del alto |
| en el piso | `juan_caido.png` | acostado, horizontal; se usa cuando cae, está atado o desmayado |

Sin espalda se usa el frente; sin agachado se aplasta el frente; sin "en el piso" el frente cae y queda acostado.

**Criaturas grandes.** Igual que una persona, con el alto que tengan en metros (`"height_m": 3.5`) y
`"kind": "creature"`. El lienzo puede ser más ancho que alto. Si la criatura es más larga que alta (el cascarudo: 2 m
de alto, 4 de largo), poné también `"length_m"` (y si querés `"width_m"`, el ancho): mientras no llegue su arte, la
figura neutra es un bloque de ese tamaño, y `tools/art_pack.py check` avisa si un modelo no sale con ese largo.

**Retrato.** Para un personaje del grupo (Juan Salvo) el HUD muestra una foto: un PNG cuadrado de 384 px o más
(`"portrait"`; si no es cuadrado se corta un cuadrado: del medio si es apaisado, de arriba si es alto, para que entren
la cabeza y los hombros). Sin retrato, una placa lisa con el nombre.

**Nombres de archivo.** En minúsculas, sin espacios ni acentos: `juan_frente.png`.

## 2. Dónde van los archivos

En `godot/art_pack/`, una carpeta por personaje o por fuente:

```
godot/art_pack/
  manifest.json
  juan_salvo/juan_salvo.glb
  juan_salvo/portrait.png
  cascarudo/cascarudo.glb
  cascarudo/cascarudo_lod.glb
  modelos/objeto.glb
```

`godot/art_pack/test/` y `godot/art_pack/stand_in/` son del juego (los dibujos de prueba y las figuras neutras): no
los toques.

Después de agregar archivos, abrí el proyecto en el editor de Godot una vez (o corré
`godot --headless --path godot --import`) para que los importe: así entran en las versiones exportadas.

## 3. El manifiesto

`godot/art_pack/manifest.json` tiene un "slot" por personaje. El id (la clave) va en minúsculas, con números y `_`.

```json
{
  "format": 1,
  "slots": {
    "juan_salvo": {
      "name": "Juan Salvo",
      "name_en": "Juan Salvo",
      "kind": "person",
      "height_m": 1.78,
      "file": "juan_salvo/juan_frente.png",
      "faces": "right",
      "portrait": "juan_salvo/retrato.png",
      "views": {
        "back": "juan_salvo/juan_espalda.png",
        "crouch": "juan_salvo/juan_agachado.png",
        "down": "juan_salvo/juan_caido.png"
      },
      "credit": {
        "author": "Nombre de quien lo dibujó",
        "licence": "Uso autorizado por el titular para el juego",
        "permission": "Permiso escrito de <titular>, 2026-10-20, guardado en <dónde>",
        "source": "Figma: <archivo>",
        "contact": "mail@ejemplo.com"
      }
    },
    "cascarudo": {
      "name": "Cascarudo",
      "kind": "creature",
      "height_m": 2.0,
      "length_m": 4.0,
      "width_m": 1.8,
      "file": "cascarudo/cascarudo.glb",
      "forward": "+z",
      "credit": {"author": "...", "licence": "...", "permission": "..."}
    }
  }
}
```

| Campo | Qué es |
|---|---|
| `name` | el nombre que se ve en el cartel de la figura neutra y en los créditos |
| `name_en` | el mismo en inglés (si no está, se usa `name`) |
| `kind` | `person`, `creature` o `prop` (objeto); decide la figura neutra (maniquí o bloque) y el alto por defecto |
| `height_m` | el alto en metros de lo dibujado (de los pies a lo más alto) |
| `file` | el dibujo de frente (PNG) o un modelo (`.glb` / `.gltf`), relativo a `art_pack/`; vacío = pendiente |
| `faces` | hacia dónde mira el dibujo: `right`, `left` o `front` |
| `length_m`, `width_m` | el largo y el ancho en metros de una criatura (el tamaño de su bloque neutro) |
| `forward` | hacia dónde mira un **modelo**, en sus propios ejes: `+z` (lo normal en glTF), `-z`, `+x` o `-x` |
| `portrait` | la foto del HUD para alguien del grupo (PNG cuadrado) |
| `views` | las vistas opcionales: `back`, `crouch`, `down` |
| `credit.author` | quién lo hizo |
| `credit.licence` | la licencia o el acuerdo con el que se usa, tal cual |
| `credit.permission` | el permiso escrito: quién lo dio, cuándo, y dónde está guardado |
| `credit.source`, `credit.contact` | de dónde salió, cómo contactar al autor (opcionales) |
| `test` | `true` solo en los dibujos de prueba (no salen en los créditos) |
| `lod` | (modelo) una copia más liviana, que se dibuja cuando la cámara está lejos |
| `clips` | (modelo con esqueleto) los nombres de sus clips: `{"idle": "Idle", "walk": "Walk", "run": "Run"}` |
| `clip_speed` | (modelo con esqueleto) a qué velocidad se hicieron sus clips: `{"walk": 0.743, "run": 2.21}` (m/s) |
| `prop` | (modelo con esqueleto) el nombre de la malla que lleva en las manos (el fusil de Juan Salvo) |
| `origin` | `model`: pararlo sobre su propio origen en vez de centrarlo (un modelo con el fusil hacia un costado) |
| `finish` | `cloth` (tela, cuero, lona) o `chitin` (caparazón): lo viste para nuestra noche (abajo); vacío = sus materiales |

Los créditos (autor, licencia y permiso de cada archivo, y la lista de lo pendiente) salen en el juego en
**Ajustes → CRÉDITOS DEL ARTE**.

## 4. Usarlo en una misión

En los datos de la misión (`godot/data/*.json`), en una unidad, un guardia o un civil (los civiles son guardias con
`"kind": "civilian"`), o en el `prisoner`:

```json
{"id": "salvo", "look": "art:juan_salvo"}
{"creatures": {"look": "art:cascarudo", ...}}
{"id": "n4", "kind": "civilian", "look": "art_pack/pruebas/figura.png", "look_height": 3.4}
```

- `"look": "art:<id>"` usa el slot del manifiesto (si no tiene archivo, la figura neutra con su cartel);
- `"look_height"` cambia el alto en metros solo para ese personaje;
- también se puede poner la ruta de un PNG directamente (las otras vistas se buscan al lado por el nombre:
  `figura_back.png`, `figura_crouch.png`, `figura_down.png`).

La figura recortada hace todo lo que hace un personaje: camina (rebota a cada paso, se balancea como un títere y se
inclina hacia donde va), se agacha, se esconde en un arbusto (se oscurece), la cargan al hombro, se cae y queda
acostada, se ve a través de las paredes (rayos X) con su color, tiene su anillo de selección y su cono de visión.

Los modelos 3D (`.glb` / `.gltf`) se paran en el lugar, escalados al alto del slot, apoyados en el piso y centrados
(no importa en qué unidades ni dónde estaba su origen), con su frente (`forward`) hacia donde camina el personaje, y se
acuestan cuando cae (una criatura se da vuelta de costado). Ver la sección 5 para los modelos de fans.

## 5. Modelos 3D de fans (esculturas)

Un modelo de fan suele ser una escultura **quieta, de muchísimos polígonos y sin esqueleto**. El juego lo aguanta así:

- **Lo escala y lo apoya solo.** Da igual si está en milímetros o en metros, o si el origen está en cualquier lado:
  el juego lo lleva al alto del slot (`height_m`), lo centra y lo para en el piso.
- **Lo hace caminar.** Si no tiene animaciones, el juego lo mueve: a una persona le da un paso con rebote, un balanceo
  de pie a pie y una inclinación hacia adelante (y respira cuando está quieta); a una criatura, un andar de bicho: un
  rebote bajo y rápido, un rolido de lado a lado, un cabeceo, y un respirar lento quieta.
- **Usa sus animaciones si las tiene.** Si el modelo trae esqueleto y animaciones, el juego las elige por el nombre,
  sin importar mayúsculas: `idle` (quieto), `walk` o `run` (caminando), `crawl` (una criatura andando), `crouch`,
  `down` / `death` / `die` (caído). Si trae una sola animación con cualquier nombre, es la de caminar (y se detiene
  cuando el personaje se para). Las de caminar y quieto se repiten en bucle.
- **Hacia dónde mira.** glTF pone el frente en +Z; si el modelo mira hacia +X (muchos exportadores lo dejan así),
  poné `"forward": "+x"` en el slot. `check` avisa cuando una criatura está echada a lo largo de X.
- **De costado arriba.** Exportá con **+Y arriba** (el exportador glTF de Blender lo hace por defecto). `check` avisa
  si una persona sale más larga de adelante a atrás que alta (exportada con Z arriba).
- **Demasiados polígonos.** `check` cuenta los triángulos: hasta **40.000** para una persona, **60.000** para una
  criatura, 20.000 para un objeto; avisa por encima y da error por encima de **ocho veces** eso, y dice cuánto
  reducir. Para reducir:

  ```
  python3 tools/art_pack.py decimate escultura.glb cascarudo.glb --faces 60000
  ```

  (usa Blender si está instalado, y conserva el esqueleto; si no, `pip install trimesh fast_simplification`, que
  pierde el esqueleto). A mano, en Blender: modificador **Decimate** (Collapse) con la proporción que dice `check`,
  aplicarlo, y **File → Export → glTF 2.0 (.glb)**.
- **Convertir.** STL, OBJ o FBX se pasan a GLB con `python3 tools/art_pack.py convert` (abajo).

**Una persona con esqueleto de persona** (cadera, pecho, dos piernas y dos brazos: así es el de Juan Salvo) se mueve
sobre sus propios huesos (`scripts/three_d/rig_person.gd`): sus clips según la velocidad (camina donde camina el grupo,
a su paso de 2,6 m/s, guiando gente o cargando a alguien, y corre solo cuando corre de verdad, desde 3 m/s; cada clip
medido a la velocidad a la que se hizo, `clip_speed`, y en paso entre sí), y lo que los clips
no traen lo arma el juego girando sus huesos, sin rehacer nada del modelo: agachado (la cadera abajo, la espalda
inclinada, las rodillas dobladas con los pies donde los pone el clip), cargando a alguien sobre el hombro (encorvado, el
paso más corto, un brazo sobre las piernas de quien lleva y el fusil colgando de la otra mano), apuntando y disparando
(el fusil al hombro y hacia el blanco, los hombros girados, la patada del tiro y el fogonazo en la boca del fusil), y
derribado (cae de espaldas y se levanta sentándose y apoyando una rodilla). Los brazos siempre buscan dónde sus manos
toman el fusil. Camina con el paso y la cadencia de los vecinos (unos 3 pasos por segundo): su clip de caminar, hecho
para 1,46 m/s, alarga el paso (cada pie va más lejos por el camino del clip y, más rápido, pasa menos tiempo en el piso,
como el de quien camina ligero), la cadera baja lo que las piernas necesitan (no más de 10 cm; pasado eso da los pasos
más seguidos en vez de más largos), y el pie apoyado no patina. **Una criatura de una pieza** (el cascarudo) se mueve
entera (`creature_body.gd`): su andar de bicho, la embestida (más baja, más rápida, con un impulso al arrancar), el ataque y el pararse en dos patas sobre quien derriba,
el trastabillar cuando recibe un tiro, y la muerte: se da vuelta panza arriba con las patas al aire. **Y si tiene
patas, las camina**: `python3 tools/art_pack.py rig-creature escultura.glb criatura.glb --lod criatura_lod.glb` le pone
un esqueleto sin tocarle la forma (cada pie o punta de pinza que toca el piso es el final de una pata; la pata sube por
la superficie hasta donde se abre al cuerpo, y la cadera, la rodilla y el tobillo quedan donde dobla), pesos que se
mezclan suave en cada articulación (nada se rompe), y en los colores de cada vértice la oclusión (las grietas y la panza
oscuras), lo convexo (los bordes gastados, más claros) y cuánto es pata o panza. Con eso el juego la hace caminar en
trípode alterno según cuánto anduvo de verdad (los pies se levantan, van adelante y se apoyan, y un pie en el piso no
patina), arrastra los pies girando en el lugar, respira con el caparazón, mueve una pata o una pinza de vez en cuando,
se estremece cuando se alerta, y levanta las pinzas al embestir y al pararse sobre alguien.

**El acabado (`finish`)** viste el modelo para la noche nevada sin cambiar su diseño
(`shaders/art_model.gdshader`; el caparazón, `shaders/art_chitin.gdshader`): sus colores y su textura (el atlas se lee nítido de lejos), mojado a medida que avanza la
noche (más oscuro y brillante), la nieve que se le va asentando arriba (la capucha y los hombros de Juan Salvo, que se le
quedan donde cayeron aunque se mueva; el lomo del cascarudo), y un borde de luz fría para que una forma oscura se
despegue de la nieve blanca. El caparazón (`chitin`) es de bicho, no de plástico: oliva pardo muy oscuro, con estrías de
crecimiento finas; en los élitros, surcos de adelante atrás con una fila de puntos y la sutura del medio (el escudo sobre
la cabeza, liso), cada costilla entre dos surcos redondeada para que los reflejos de los faroles se corten en cada línea,
y unas líneas de placa en los flancos; picado fino, pulido en la cúpula y mate y polvoriento en las juntas y la panza (que
es más oscura), los bordes y los labios de los surcos gastados más claros; la noche reflejada en lo pulido (el cielo
oscuro arriba, el resplandor cálido de la ciudad en el horizonte con algún farol, la nieve abajo), un tornasol de aceite
(azul, verde, bronce) solo en lo rasante, la luz de la nieve que le rebota desde abajo, y el de los faroles mojado. De
cerca (un primer plano, el tráiler) el tono sube un poco y las patas y la panza se leen; desde la cámara del juego queda
como siempre, una forma oscura sobre la nieve. En el modo historieta el borde y el brillo se apagan y
el caparazón se imprime oscuro. Un modelo que trae su horneado (`refine-person`: Juan Salvo) se viste como la ropa de
los vecinos: el alfa de su atlas dice qué es cada muestra (sarga, lona, tela acolchada, cuero, goma, acero, vidrio,
piel), y cada una tiene su trama fija sobre la tela, su aspereza y su brillo; sus colores van al rango de la noche (no más
claros ni más saturados que los de los vecinos, el mismo tono), con la sombra de sus pliegues, el barro de abajo, los
bordes gastados y el brillo suave de borde de los vecinos, y unos copos en la coronilla desde el principio, como en
las gorras de los vecinos. Toda la figura de Juan Salvo es una sola llamada de dibujo (sus prendas y el fusil
juntados sobre su esqueleto); ninguno de los dos echa sombra del cielo en la Plaza (como ninguna figura allí).

Para probar todo esto sin arte con licencia están los modelos de prueba neutros: `test/capsule.glb` (una cápsula
quieta, modelada en centímetros y corrida de su origen), `test/crawler.glb` (un bloque quieto con el frente en +X) y
`test/rigged.glb` (un poste con dos huesos y animaciones `Idle` y `Walk`), hechos por `tools/art_pack.py test-models`.

## 6. Revisar los archivos

```
python3 tools/art_pack.py check
```

Revisa el manifiesto y cada archivo: que exista, que sea PNG con fondo transparente, que la figura llene el lienzo, que los pies toquen el borde de abajo, que no tenga
demasiado semitransparente, y que **cada archivo tenga autor, licencia y permiso**. En un modelo: sus triángulos
contra el presupuesto, su tamaño tal como está modelado y cómo queda en el juego, hacia dónde está echado, y si tiene
esqueleto y qué animaciones usa el juego (sección 5). (Recomendado: al menos 1024 px
del lado largo; avisa por debajo de 512 y por encima de 4096.) Avisa también si en la licencia
aparece algo que suele no servir (uso personal, no comercial, sin obras derivadas, Cults3D, "todos los derechos
reservados"). Sale con error si falta algo obligatorio; `--strict` cuenta también los avisos.

Para convertir modelos que vos agregues:

```
python3 tools/art_pack.py convert pieza.stl pieza.glb    # STL y OBJ (necesita: pip install trimesh)
python3 tools/art_pack.py convert pieza.fbx pieza.glb    # FBX: necesita Blender o assimp instalados
```

## 7. Licencias y permisos: revisá cada archivo

- **Cada archivo tiene su propia licencia.** Antes de agregarlo, fijate cuál es y copiala tal cual en
  `credit.licence`.
- **Sketchfab**: cada modelo lleva su licencia (CC BY, CC BY-NC, CC BY-ND, "Standard", "Editorial"...). CC BY pide
  crédito al autor; NC prohíbe el uso comercial; ND prohíbe modificarlo (recortarlo, escalarlo o pintarlo ya es
  modificar); "Editorial" no sirve para un juego.
- **Cults3D**: los archivos suelen venderse para **uso personal** (imprimirlos en casa): no sirven para mostrarlos en un
  juego.
- **Fan art**: aunque el artista te dé permiso, hace falta además el del titular de los derechos de los personajes.
- **El permiso del titular de los derechos, por escrito**: guardá el mail o el PDF fuera del repositorio (o en una
  carpeta privada), y anotá en `credit.permission` quién lo dio, cuándo y dónde está guardado. Si el permiso es solo
  para una versión determinada del juego, dejalo dicho ahí.
- No subas a un repositorio público arte que no tenga permiso para eso. `juan_salvo/`, `cascarudo/` y los vehículos
  (`godot/assets/vehicles/`, `art/vehicles/`) están acá porque sus autores lo permitieron, y solo para usar con Hora
  Cero: no son MIT ni CC BY.

## 8. El modo historieta

**Ajustes → MODO HISTORIETA (SÍ / NO)** dibuja la operación como tinta negra sobre papel de diario: contornos
gruesos, rayado y doble rayado en las sombras, negros llenos, blancos de papel en la nieve y en las luces, un poco de
trama de puntos y el grano del papel. La interfaz (HUD) y lo que es del juego (los conos de visión, los recorridos,
los marcadores) mantienen sus colores, como una segunda tinta.

Para que un nivel se vea siempre así: `"ink": true` en sus datos. En una exportación, la característica (feature)
`comic_ink` también lo prende; para una versión web ya dibujada en tinta: `python3 tools/web_site_build.py --ink
<carpeta>`.

Tus dibujos en ese modo: el juego les vuelve a pasar la tinta (los grises quedan rayados según lo oscuros que sean),
así que los rellenos planos y los negros llenos se ven mejor que los degradés.

---

## English summary

- **What it is.** `godot/art_pack/` holds art made with permission, listed in `manifest.json` (one slot per
  character, creature or prop). Data looks `"art:<slot>"` (or a PNG path) show it as a **paper cut-out** (a flat
  drawing on a card that faces the camera, with a thick ink outline and a white paper rim; it bobs, rocks and leans when
  walking, flips with direction, squashes or swaps to the crouch drawing, lies flat when down, rides on a shoulder
  when carried, x-rays through walls) or a `.glb`/`.gltf` model. A slot with no file shows a **neutral grey mannequin
  (or block) with a plate: LICENSED ART PENDING · <name>**. `look_height` (metres) overrides the height per actor.
- **Drawing in Figma.** Portrait frame, 1024 × 2048 px for a person, feet on the bottom edge, small margins;
  standing three-quarter view facing right; transparent background, export PNG; outer stroke about 1 % of the height
  (18–20 px), inner lines 8–10 px, flat fills (white, 2–3 greys, black), no detail finer than ~6 px, nothing
  half-transparent inside the figure. Optional views: back, crouch (shown at 72 % height), down (lying, horizontal).
- **Manifest fields.** `name`, `name_en`, `kind` (person/creature/prop), `height_m`, `length_m` and `width_m` (a
  creature's size: its neutral stand-in is a plain grey block of that size lying the way it walks), `file`, `faces`
  (right/left/front), `forward` (a model's front: +z by glTF's custom, -z, +x, -x), `portrait` (the HUD's ID photo for
  one of the squad; a plain plate with the name until it comes), `views {back, crouch, down}`, `credit {author,
  licence, permission, source, contact}`, `test`; and for a model `lod` (a lighter copy drawn while the camera is far),
  `clips` and `clip_speed` (a rigged person's clips by role and the speeds they were made at), `prop` (the mesh he holds),
  `origin` ("model": stand it on its own origin, not centred), `finish` ("cloth" / "chitin": dressed for our night).
  Credits appear under Settings → ART CREDITS.
- **The Plaza de Mayo's slots.** `juan_salvo` and `cascarudo` are licensed models by Santiago Siri, used with the
  maker's and the rights holders' permission. They are **in the repository with that permission, for use with Hora
  Cero, but not under its free licences** (not MIT, not CC BY: all rights reserved by their authors; each folder's
  `CREDITS.txt`, and NOTICE): `juan_salvo/juan_salvo.glb` (since 20 October 2026: a blue-suit survivor, a Meshy AI
  biped on a 61-bone Mixamo skeleton, 10,390 triangles in one mesh with 2K maps; `tools/juan_suit.py` bakes it into
  metres and Y up, gives it a standing rest with the rifle across his chest in both hands (its grip and fingers from
  its RunShoot clip), adds the previous Juan's rifle on a bone of its own (`art/juan_salvo/source/rifle.glb`), indexes
  the mesh and keeps Idle/Walk/Run/Jump, made for 1.46 and 5.21 m/s; its portrait is the avatar that came with it. Of
  the previous Juans, Ale's blue-hood one is remade by `tools/juan_blue_hood.py`; the first one, refined by
  `refine-person`, is no longer in this repository); `cascarudo/cascarudo.glb` (the sculpt, 45k triangles, its shape
  untouched, its legs rigged by `tools/art_pack.py rig-creature`; shown 4 m long, 3.27 m high) and
  `cascarudo/cascarudo_lod.glb` (13.5k, rigged alike, for far views). The same goes for what was made from them (the
  game's icon, a render of the cascarudo) and for the Plaza's vehicles. Remove the folders and empty the slots'
  `file`, `portrait` and `lod`, and the neutral stand-ins show (and the kit's own colectivo and cars).
- **A rigged person** (hips, chest, two legs, two arms) is moved on its own skeleton (`rig_person.gd`): its clips blended
  by speed and phase-matched (walking wherever the squad walks, up to its 2.6 m/s, leading or carrying; its run only for
  real running, from 3 m/s), plus bone offsets for crouching (leg reach keeps the feet), carrying someone over the
  shoulder (bent, slower, one arm over the legs, the prop in the other hand), aiming and firing (prop to the shoulder on
  the line to the target, recoil, the flash at the prop's muzzle), knocked down and getting up (keyed poses); its arms
  always reach for where its hands hold the prop; it walks at the neighbours' stride and cadence (about 3 steps a
  second): the clip's foot path drawn out and retimed (less of each step on the ground as it goes faster), the hips let
  down to reach (at most 10 cm; past that, quicker steps rather than longer), planted feet kept still. **A one-piece
  creature** is moved whole (`creature_body.gd`): crawl, rush with a lunge, strike and rear up over the one it knocks
  down, a stagger when shot, a death roll onto its back.
  **Its legs walk** once `rig-creature src.glb out.glb --lod out_lod.glb` (tools/creature_rig.py) has rigged it, its
  shape untouched: each ground contact is a foot; the limb runs up the surface (geodesic bands) to where it opens out
  into the body (the hip); knee and ankle at the best three-piece fit of its middle line; smooth weights at every joint;
  per-vertex occlusion, convexity and leg/underside baked into its colours (and its rest position into its UVs). The
  game drives an alternating tripod from the ground actually covered (feet lift, swing to where they will be needed and
  plant without skating; bob and sway in step; feet shuffle when turning on the spot), the shell breathes, legs shift and
  claws or head twitch at rest, a shudder when alerted, claws flung up when it rushes and when it rears.
  **A finish** (`art_model.gdshader`) keeps the model's colours and design: a crisp atlas, wet as the night goes on,
  snow settling on top (kept where it settled on a skinned figure), a cold rim; cloth that brings its own bake
  (refine-person: Juan Salvo) dressed as the neighbours' clothes are (the atlas's alpha names each swatch's material: its
  grain fixed on the cloth, roughness and sheen; baked occlusion, mud, worn edges and folds; colours held to the night's
  range, hues kept; the neighbours' soft edge sheen in place of most of the rim; a few flakes on the crown); the chitin
  (`art_chitin.gdshader`) a beetle's carapace: a very dark olive-brown; growth ridges, striae along the wing cases
  (punctured, the midline's suture, the plate over the head smooth) with each rib rounded so the lamps' highlights
  break at every line, plate lines on the flanks; pitted, polished crown and matte dusty joints and underside, worn
  edges and lips; the night reflected in its gloss (dark sky, the city's warm glow and lamps' glints on the horizon,
  the snow below), an oil-slick film only at grazing angles, the snow's light bounced up under it, the lamps' wet
  highlights; close to the lens its tone lifts a little so the legs and plates read, while from the game's camera it
  stays a dark shape on the snow; in comic ink no rim or sheen. A rigged figure's pieces are merged into one draw call;
  no sky shadows on the Plaza.
- **Fan models (static, high-poly sculpts).** Scaled to `height_m`, grounded and centred whatever their units and
  origin; front turned the way they walk (`forward`); a static model is moved by the game (a person steps, sways, leans
  and breathes; a creature crawls: a quick low bob, a side-to-side roll, a nod); a rigged one plays its own animations
  by name, any case (idle, walk/run, crawl, crouch, down/death/die; a single animation is the walk), looped; a creature
  rolls onto its side when it falls. `check` counts triangles against a budget (person 40k, creature 60k, prop 20k;
  error at 8x) and gives the decimation ratio; `decimate in.glb out.glb --faces N` uses Blender (keeps the rig) or
  trimesh + fast_simplification. It also reports the size as modelled and as shown, Z-up exports and creatures lying
  along X. Neutral test models: `test-models` (a static capsule in centimetres off its origin, a static block whose front
  is +x, a rigged post with "Idle" and "Walk").
- **Checking.** `python3 tools/art_pack.py check` validates the manifest and files (size, transparency, fill, feet,
  credits, risky licences; a model's triangles, proportions, rig and animations); `convert` turns STL/OBJ (trimesh) or
  FBX (Blender/assimp) into GLB. Run the Godot import
  after adding files so exports include them.
- **Licences.** Every file carries its own licence; Sketchfab models each have theirs (CC BY needs credit, NC no
  commercial use, ND no modification, Editorial not for games); Cults3D files are usually personal-use only; fan art
  needs the rights holder's permission too. Keep the rights holder's written permission (outside the repo) and record
  who/when/where in `credit.permission`.
- **Comic ink.** Settings → COMIC INK, or `"ink": true` in a level's data, or the export feature `comic_ink`
  (`tools/web_site_build.py --ink <out>`).
