extends Button
## Field-kit plate button used for every HUD control (action slots, ID-photo portraits, camera and
## menu keys, the dossier's buttons), plus the small shared "kit" the HUD and recon map draw with:
## palette, bundled fonts, the glyph, 3D icon and medal atlases and a 2x-density nine-slice helper.
##
## All UI textures are authored at 2 px per logical HUD pixel and drawn at half scale, so plates stay
## crisp on a retina phone. Margins/bleeds below are in texture pixels (see tools/gen_ui_textures.py).

# --- palette (small on purpose) -------------------------------------------------------------------
const IVORY := Color("ece6d2")   # primary text
const MUTED := Color("bdb8a0")   # secondary text
const KHAKI := Color("b3a67d")   # canvas, small-caps labels
const BRASS := Color("e0ad4c")   # the one accent: selection, "live" actions
const RED := Color("d9482f")     # reserved for detection / alarm / wounds
const INK := Color("24251e")     # text on paper and canvas
const DIM := Color("7f8473")     # disabled glyphs and labels
const COLD := Color("b8cfe6")    # the cold a rescue's people and squad take in the snow

const TexPlate := preload("res://assets/ui/plate.png")
const TexPlatePressed := preload("res://assets/ui/plate_pressed.png")
const TexPlateArmed := preload("res://assets/ui/plate_armed.png")
const TexGun := preload("res://assets/ui/plate_gun.png")
const TexGunPressed := preload("res://assets/ui/plate_gun_pressed.png")
const TexTape := preload("res://assets/ui/tape.png")
const TexStrip := preload("res://assets/ui/strip.png")
const TexPhotoFrame := preload("res://assets/ui/photo_frame.png")
const TexGlyphs := preload("res://assets/ui/glyphs.png")
const TexIcons3D := preload("res://assets/ui/icons3d.png")
const TexMedals := preload("res://assets/ui/medals.png")
const TexEdge := preload("res://assets/ui/edge_glow.png")
const FontSemi := preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const FontMedium := preload("res://assets/fonts/BarlowCondensed-Medium.ttf")
const FontType := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const FontStencil := preload("res://assets/fonts/BigShouldersStencilDisplay-wght.ttf")

const PLATE_MARGIN := 24.0
const PLATE_BLEED := 8.0
const TAPE_BLEED := 4.0
const GLYPH_CELL := 96.0
const GLYPH_COLS := 6
const GLYPHS := [
	"crouch","walk","throw","key","cell","rescue",
	"boat","pause","play","rot_l","rot_r","brief",
	"knife","bind","pistol","revolver","tripwire","cutters",
	"radio","carry","drop","hide","flag","tap",
	"drag","pinch","target","eye","clock","cross",
	"limpet","charge","switch","cigarette","gate","cosh",
	"bottle","uniform","rope","talk","skis","phone",
	"smg","snowsuit","window","duct"]
## The kit as rendered 3D objects (tools/icons3d; `finish.py atlas` builds icons3d.png in this order): full colour
## in ICON3D_CELL px cells, ICON3D_COLS across, and the same cells again in grey below them for an action that is
## disabled or recharging. A name listed here draws from this atlas instead of the flat GLYPHS one; the UI and
## gesture glyphs (crouch, walk, pause, tap, eye...) stay flat.
const ICON3D_CELL := 192.0
const ICON3D_COLS := 8
const ICONS3D := [
	"throw","key","cell","boat","brief","knife","bind","pistol",
	"revolver","tripwire","cutters","radio","hide","flag","clock","limpet",
	"charge","switch","cigarette","gate","cosh","bottle","uniform","rope",
	"skis","phone","smg","snowsuit","window","duct","lampkey","bell",
	"papers","oars","handle","cord","ladder","cellar","lampboard","gondola",
	"rowboat","flatcap","motorcap","hand","tram","subte","tarp","stretcher"]
## A 3D icon is drawn this much larger or smaller than a flat glyph asked for at the same size, to look as big.
const ICON3D_SCALE := 1.0
## Where the ink edge of a 3D icon on paper is drawn from (times about a pixel): all round the object.
const HALO := [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1),Vector2(0.7,0.7),Vector2(-0.7,0.7),Vector2(0.7,-0.7),Vector2(-0.7,-0.7)]
## Debrief medals (medals.png, BADGES order): struck brass on the top row, grey for an earlier run's below, and
## on the third row a brighter one with the symbol inked on, for the small sizes (MEDAL_SMALL px and under).
const BADGES := ["ghost","clean_hands","not_a_shot","saboteur","swift"]
const MEDAL_CELL := 192.0
const MEDAL_SMALL := 40.0
## The medal fills more of its cell than the old ink stamp did.
const MEDAL_SCALE := 0.96
## Caption sizes tried in turn until the words fit their plate: [font px, tracking].
const FIT_STEPS := [[22,2],[21,1],[19,1],[18,0],[16,0]]

static var _fonts: Dictionary = {}
static var _fits: Dictionary = {}
static var _seconds: PackedStringArray = PackedStringArray()
static var _empty := StyleBoxEmpty.new()
static var _icons3d: CanvasTexture
static var _medals: CanvasTexture

## Bundled face with optional tracking (extra px between glyphs). kind: semi | medium | type | stencil.
static func face(family: String, tracking: int = 0) -> Font:
	var key: String = family+str(tracking)
	if _fonts.has(key): return _fonts[key]
	var f := FontVariation.new()
	match family:
		"semi": f.base_font = FontSemi
		"medium": f.base_font = FontMedium
		"type": f.base_font = FontType
		"stencil":
			f.base_font = FontStencil
			f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 760}
	# Tabular figures keep the mission clock and countdowns from jittering.
	if family == "semi" or family == "medium":
		f.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	f.spacing_glyph = tracking
	_fonts[key] = f
	return f

## Whole numbers 0..99 as ready-made strings, so a countdown never builds one while drawing.
static func number(value: int) -> String:
	if _seconds.is_empty():
		for i: int in range(100): _seconds.append(str(i))
	return _seconds[clampi(value,0,99)]

## Largest caption style from FIT_STEPS in which `value` is no wider than `room` (cached).
static func fit(value: String, room: float) -> Array:
	var key: String = value+"|"+str(int(room))
	if _fits.has(key): return _fits[key]
	var best: Array = FIT_STEPS[FIT_STEPS.size()-1]
	for step: Array in FIT_STEPS:
		if face("semi",step[1]).get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,step[0]).x-step[1] <= room:
			best = step
			break
	_fits[key] = best
	return best

## Draws a 2x nine-slice (tiled centre) over `rect` (logical px). `bleed` is the texture's shadow skirt.
static func nine(item: CanvasItem, tex: Texture2D, rect: Rect2, margin: float, bleed: float, tint: Color = Color.WHITE, center: bool = true, fit_tiles: bool = false) -> void:
	var r := rect.grow(bleed*0.5)
	var mode := RenderingServer.NINE_PATCH_TILE_FIT if fit_tiles else RenderingServer.NINE_PATCH_TILE
	item.draw_set_transform(r.position,0.0,Vector2(0.5,0.5))
	RenderingServer.canvas_item_add_nine_patch(item.get_canvas_item(),Rect2(Vector2.ZERO,r.size*2.0),Rect2(Vector2.ZERO,tex.get_size()),tex.get_rid(),Vector2(margin,margin),Vector2(margin,margin),mode,mode,center,tint)
	item.draw_set_transform(Vector2.ZERO)

## Draws one glyph centred on `at`, `px` logical pixels tall. A flat glyph takes `tint`; a 3D object keeps its
## own colours and takes only the tint's alpha, or turns grey when the tint is DIM (disabled, recharging).
static func glyph(item: CanvasItem, which: String, at: Vector2, px: float, tint: Color) -> void:
	var k: int = ICONS3D.find(which)
	if k >= 0:
		if _icons3d == null: _icons3d = _mipmapped(TexIcons3D)
		var rows: int = ceili(float(ICONS3D.size())/ICON3D_COLS)
		var grey: bool = absf(tint.r-DIM.r)+absf(tint.g-DIM.g)+absf(tint.b-DIM.b) < 0.03
		var cell := Vector2(k%ICON3D_COLS,floori(float(k)/ICON3D_COLS)+(rows if grey else 0))*ICON3D_CELL
		var side: float = px*ICON3D_SCALE
		var dest := Rect2((at-Vector2(side,side)*0.5).round(),Vector2(side,side))
		var src := Rect2(cell,Vector2(ICON3D_CELL,ICON3D_CELL))
		if tint.get_luminance() < 0.3:
			# An ink tint means paper, where the ivory rim melts into the page: an ink edge keeps the object's shape.
			var reach: float = maxf(1.0,px/30.0)
			for step: Vector2 in HALO: item.draw_texture_rect_region(_icons3d,Rect2(dest.position+step*reach,dest.size),src,Color(INK,tint.a*0.6))
		item.draw_texture_rect_region(_icons3d,dest,src,Color(1,1,1,tint.a))
		return
	var i: int = GLYPHS.find(which)
	if i < 0: return
	var src := Rect2(Vector2(i%GLYPH_COLS,floori(float(i)/GLYPH_COLS))*GLYPH_CELL,Vector2(GLYPH_CELL,GLYPH_CELL))
	item.draw_texture_rect_region(TexGlyphs,Rect2((at-Vector2(px,px)*0.5).round(),Vector2(px,px)),src,tint)

## Draws one debrief medal centred on `at`, `px` logical pixels across. A faint tint (alpha under 0.5: earned on
## an earlier run) draws it ghosted, grey and see-through; otherwise it is struck brass, inked when small.
static func badge(item: CanvasItem, which: String, at: Vector2, px: float, tint: Color) -> void:
	var i: int = BADGES.find(which)
	if i < 0: return
	if _medals == null: _medals = _mipmapped(TexMedals)
	var ghost: bool = tint.a < 0.5
	var row: float = 1.0 if ghost else (2.0 if px <= MEDAL_SMALL else 0.0)
	var side: float = px*MEDAL_SCALE
	var shade := Color(1,1,1,clampf(tint.a*2.0,0.25,0.5)) if ghost else Color(1,1,1,clampf(tint.a/0.9,0.0,1.0))
	item.draw_texture_rect_region(_medals,Rect2((at-Vector2(side,side)*0.5).round(),Vector2(side,side)),Rect2(i*MEDAL_CELL,row*MEDAL_CELL,MEDAL_CELL,MEDAL_CELL),shade)

## The rendered atlases are drawn well below their size: sample them through their mipmaps so the edges stay
## clean (a plain linear filter would shimmer at map-pin size).
static func _mipmapped(tex: Texture2D) -> CanvasTexture:
	var t := CanvasTexture.new()
	t.diffuse_texture = tex
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return t

## Caps label centred on x, with its baseline at y (compensates the trailing tracking).
static func label(item: CanvasItem, f: Font, value: String, center_x: float, baseline_y: float, px: int, tint: Color) -> void:
	var w: float = f.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	if f is FontVariation: w -= (f as FontVariation).spacing_glyph
	item.draw_string(f,Vector2(roundf(center_x-w*0.5),baseline_y),value,HORIZONTAL_ALIGNMENT_LEFT,-1,px,tint)

## Gauge ring: a dark track with `fraction` of it filled clockwise from twelve o'clock.
static func ring(item: CanvasItem, center: Vector2, radius: float, fraction: float, width: float, tint: Color, track: Color = Color(0.03,0.04,0.03,0.82)) -> void:
	item.draw_arc(center,radius,0.0,TAU,40,track,width+2.0,true)
	if fraction > 0.004: item.draw_arc(center,radius,-PI*0.5,-PI*0.5+TAU*clampf(fraction,0.0,1.0),40,tint,width,true)

# --- the button -----------------------------------------------------------------------------------
## slot (an action-bar slot) · portrait · rotate_left | rotate_right · text · primary · secondary
var kind: String = ""
## Slot: glyph name from the atlas.
var symbol: String = "": set = set_symbol
## "Live" accent: the action being aimed, EXECUTE while orders are queued.
var armed: bool = false: set = set_armed
## The action cannot be used right now. The plate looks dead but still takes the tap, so the HUD can say why.
var dimmed: bool = false: set = set_dimmed
## Slot: this is the operative's current order.
var active: bool = false: set = set_active
## Slot: rounds or tripwires left, drawn as a magazine of pips (negative hides it).
var count: int = -1: set = set_count
var count_max: int = 0: set = set_count_max
## Slot: recharge progress 0..1 drawn as a ring around the glyph (negative hides it), and the
## whole seconds still to wait (negative hides the figure).
var progress: float = -1.0: set = set_progress
var wait: int = -1: set = set_wait
## Portrait: this operative is the selected one.
var selected: bool = false: set = set_selected
## Portrait: health in three steps (3 = unhurt … 1 = one more hit kills, 0 = down).
var health: int = 3: set = set_health
## Portrait, in a rescue (data "snowfall"): the cold he has taken, 0..1, as a bar in place of the health blocks
## (negative: the health blocks).
var cold: float = -1.0: set = set_cold
## Portrait: atlas texture and the square region holding this operative's ID photo.
var photo: Texture2D
var photo_region: Rect2
## Portrait with no photo yet (one of the squad dressed from the art pack, its portrait still to come): a plain paper
## plate in the window with this name on it.
var photo_plate: String = "": set = set_photo_plate
## Portrait: a band across the photo saying where he is ("ON HIS WAY" before he comes), "" for none.
var band: String = "": set = set_band

func set_photo_plate(value: String) -> void:
	if photo_plate == value: return
	photo_plate = value
	queue_redraw()

func set_band(value: String) -> void:
	if band == value: return
	band = value
	queue_redraw()

func set_symbol(value: String) -> void:
	if symbol == value: return
	symbol = value
	queue_redraw()

func set_armed(value: bool) -> void:
	if armed == value: return
	armed = value
	queue_redraw()

func set_dimmed(value: bool) -> void:
	if dimmed == value: return
	dimmed = value
	queue_redraw()

func set_active(value: bool) -> void:
	if active == value: return
	active = value
	queue_redraw()

func set_count(value: int) -> void:
	if count == value: return
	count = value
	queue_redraw()

func set_count_max(value: int) -> void:
	if count_max == value: return
	count_max = value
	queue_redraw()

func set_progress(value: float) -> void:
	# Quantised to the ring's visible steps so a recharge repaints the plate about 60 times, not every tick.
	var stepped: float = -1.0 if value < 0.0 else roundf(value*64.0)/64.0
	if is_equal_approx(progress,stepped): return
	progress = stepped
	queue_redraw()

func set_wait(value: int) -> void:
	if wait == value: return
	wait = value
	queue_redraw()

func set_selected(value: bool) -> void:
	if selected == value: return
	selected = value
	queue_redraw()

func set_health(value: int) -> void:
	if health == value: return
	health = value
	queue_redraw()

func set_cold(value: float) -> void:
	var stepped: float = -1.0 if value < 0.0 else roundf(value*40.0)/40.0
	if is_equal_approx(cold,stepped): return
	cold = stepped
	queue_redraw()

func _ready() -> void:
	# The plate, glyph and label are all drawn in _draw; silence the stock Button skin.
	focus_mode = Control.FOCUS_NONE
	for key: String in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_disabled_color","font_focus_color"]:
		add_theme_color_override(key,Color.TRANSPARENT)
	for key: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		add_theme_stylebox_override(key,_empty)
	# A bar plate is as wide as the bar lays it out and fits its own label to that (fit() in _draw_slot): the stock
	# Button's text must not widen it, or a long label (LUCES DE LA RECOVA) pushes the plate under the next one and it
	# stays that wide for the next operative's bar.
	if kind == "slot": clip_text = true

func _draw() -> void:
	var mode := get_draw_mode()
	var down: bool = mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
	var hover: bool = mode == DRAW_HOVER
	var rect := Rect2(Vector2.ZERO,size)
	var nudge := Vector2(0,1) if down else Vector2.ZERO
	match kind:
		"portrait": _draw_portrait(rect,down,hover)
		"slot": _draw_slot(rect,down,hover,nudge)
		_: _draw_key(rect,down,hover,nudge)

## Camera and menu keys (gun-metal) and the dossier's buttons (brass-keyed primary, olive secondary).
func _draw_key(rect: Rect2, down: bool, hover: bool, nudge: Vector2) -> void:
	var dark: bool = kind == "text" or kind == "rotate_left" or kind == "rotate_right"
	var bright: bool = kind == "primary" and not dimmed
	# a lit secondary key is the current choice of a row of them (the dossier's mission tabs)
	var lit: bool = armed and kind == "secondary"
	var tex: Texture2D = TexGun if dark else (TexPlateArmed if bright or lit else TexPlate)
	if down: tex = TexGunPressed if dark else (TexPlateArmed if bright or lit else TexPlatePressed)
	var tint := Color.WHITE
	if disabled or dimmed: tint = Color(0.66,0.66,0.66,0.92)
	elif down and bright: tint = Color(0.8,0.8,0.8)
	elif hover: tint = Color(1.14,1.14,1.14)
	nine(self,tex,rect,PLATE_MARGIN,PLATE_BLEED,tint)
	var c: Color = DIM if (disabled or dimmed) else (MUTED.lerp(IVORY,0.5) if dark else (BRASS if lit else IVORY))
	var mid: float = size.x*0.5
	# the words in the player's language (lang.gd); a long one is set smaller to fit the plate
	var shown: String = tr(text)
	match kind:
		"primary":
			var big: Array = fit(shown,size.x-24) if face("semi",3).get_string_size(shown,HORIZONTAL_ALIGNMENT_LEFT,-1,26).x > size.x-24 else [26,3]
			label(self,face("semi",int(big[1])),shown,mid,roundf(size.y*0.5+int(big[0])*0.35)+nudge.y,int(big[0]),c)
		"rotate_left": glyph(self,"rot_l",rect.get_center()+nudge,40,c)
		"rotate_right": glyph(self,"rot_r",rect.get_center()+nudge,40,c)
		_:
			var style: Array = fit(shown,size.x-22)
			label(self,face("semi",style[1]),shown,mid,roundf(size.y*0.5+style[0]*0.36)+nudge.y,style[0],c)

func _draw_slot(rect: Rect2, down: bool, hover: bool, nudge: Vector2) -> void:
	var dead: bool = disabled or dimmed
	var tex: Texture2D = TexPlateArmed if armed else (TexPlatePressed if down else TexPlate)
	var tint := Color.WHITE
	if disabled: tint = Color(0.66,0.66,0.66,0.92)
	elif dimmed: tint = Color(0.74,0.74,0.74,0.95)
	elif down and armed: tint = Color(0.8,0.8,0.8)
	elif hover: tint = Color(1.14,1.14,1.14)
	nine(self,tex,rect,PLATE_MARGIN,PLATE_BLEED,tint)
	var c: Color = DIM if dead else (BRASS if armed else IVORY)
	var mid: float = size.x*0.5
	var at := Vector2(mid,34)+nudge
	var cooling: bool = progress >= 0.0 and progress < 1.0
	glyph(self,symbol,at,44,DIM if cooling else c)
	if cooling:
		ring(self,at,27.0,progress,3.0,BRASS.darkened(0.05),Color(0.03,0.04,0.03,0.6))
		if wait >= 0: label(self,face("semi",0),number(wait),size.x-20.0,26.0+nudge.y,20,MUTED)
	var shown: String = tr(text)
	var style: Array = fit(shown,size.x-18)
	label(self,face("semi",style[1]),shown,mid,size.y-15+nudge.y,style[0],MUTED if (cooling and not armed) else c)
	if count_max > 0 and count >= 0 and not cooling:
		# Magazine: one pip per round or wire, emptied from the top.
		var x: float = size.x-21.0
		for i: int in range(count_max):
			var pip := Rect2(x,12.0+i*6.0+nudge.y,9.0,4.0)
			var left: bool = i >= count_max-count
			draw_rect(pip.grow(1.0),Color(0.03,0.04,0.03,0.7))
			draw_rect(pip,(DIM if dead else BRASS) if left else Color(0.2,0.22,0.18))
	if active and not disabled:
		# Lamp: this is what the operative is doing (or will do on EXECUTE).
		draw_circle(Vector2(15,15)+nudge,5.5,Color(0.03,0.04,0.03,0.85),true,-1.0,true)
		draw_circle(Vector2(15,15)+nudge,3.5,BRASS,true,-1.0,true)

func _draw_portrait(rect: Rect2, down: bool, hover: bool) -> void:
	# An ID photo clipped into a steel holder, with a canvas name tape underneath.
	var fallen: bool = health <= 0
	var live: bool = selected and not disabled and not fallen
	var tint := Color(0.7,0.7,0.7) if disabled else (Color(1.12,1.12,1.12) if hover else Color.WHITE)
	nine(self,TexPlatePressed if down else TexPlate,rect,PLATE_MARGIN,PLATE_BLEED,tint)
	var inset := 7.0
	var tape_h := 26.0
	var window := Rect2(inset,inset,size.x-inset*2,size.y-inset*3-tape_h)
	if photo:
		# Cover-crop the square source to the window, biased slightly upward to keep the face centred.
		var src := photo_region
		var want: float = window.size.x/window.size.y
		if want < 1.0:
			var w: float = src.size.y*want
			src = Rect2(src.position.x+(src.size.x-w)*0.5,src.position.y,w,src.size.y)
		else:
			var h: float = src.size.x/want
			src = Rect2(src.position.x,src.position.y+(src.size.y-h)*0.35,src.size.x,h)
		var shade: Color = Color.WHITE if live else (Color(0.42,0.43,0.40) if (disabled or fallen) else Color(0.60,0.61,0.57))
		draw_texture_rect_region(photo,window,src,shade)
	elif photo_plate != "":
		# no photo yet: a plain paper plate with the name, the way the stand-in in the world wears it
		var paper := Color(0.93,0.91,0.85) if live else Color(0.72,0.71,0.66)
		draw_rect(window,Color(0.2,0.2,0.19))
		var card := window.grow(-6.0)
		draw_rect(card,paper)
		draw_rect(card,INK,false,2.0)
		var words: PackedStringArray = photo_plate.split(" ",false)
		var px: int = 22 if words.size() <= 2 else 18
		var line_h: float = px+2.0
		var top: float = card.get_center().y-line_h*words.size()*0.5+px*0.82
		for i: int in range(words.size()):
			label(self,face("semi",2),words[i],size.x*0.5,top+line_h*i,px,INK)
	nine(self,TexPhotoFrame,window,28.0,0.0,Color.WHITE,false)
	# Health: three blocks along the foot of the photo; the last one turns red.
	var gap := 3.0
	var block := Vector2(floorf((window.size.x-12.0-gap*2.0)/3.0),6.0)
	var base := Vector2(window.position.x+6.0,window.end.y-block.y-6.0)
	draw_rect(Rect2(base-Vector2(2,2),Vector2(block.x*3.0+gap*2.0+4.0,block.y+4.0)),Color(0.03,0.04,0.03,0.78))
	if cold >= 0.0:
		# the cold: one bar filling from pale to brass to red as the snow gets into him
		var whole := Vector2(block.x*3.0+gap*2.0,block.y)
		draw_rect(Rect2(base,whole),Color(0.16,0.19,0.24))
		if cold > 0.01:
			var tone: Color = COLD.lerp(BRASS,smoothstep(0.35,0.6,cold)).lerp(RED,smoothstep(0.7,0.9,cold))
			draw_rect(Rect2(base,Vector2(maxf(2.0,roundf(whole.x*clampf(cold,0.0,1.0))),whole.y)),tone)
	else:
		for i: int in range(3):
			var cell := Rect2(base+Vector2(i*(block.x+gap),0),block)
			if i < health: draw_rect(cell,RED if health == 1 else (BRASS if health == 2 else Color(IVORY,0.86)))
			else: draw_rect(cell,Color(0.26,0.12,0.09) if health < 3 else Color(0.2,0.22,0.18))
	if fallen and band == "":
		var strip := Rect2(window.position.x,window.get_center().y-13.0,window.size.x,26.0)
		draw_rect(strip,Color(RED.darkened(0.35),0.92))
		label(self,face("semi",3),tr("DOWN"),size.x*0.5,strip.end.y-6.0,22,IVORY)
	elif band != "":
		# not here yet, or the like: a khaki band
		var strip := Rect2(window.position.x,window.get_center().y-12.0,window.size.x,24.0)
		draw_rect(strip,Color(0.12,0.13,0.1,0.9))
		label(self,face("semi",2),tr(band),size.x*0.5,strip.end.y-6.0,18,KHAKI)
	elif live:
		# Accent frame: crisp brass keyline around the window.
		draw_rect(window.grow(1.0),BRASS,false,2.0)
	var tape := Rect2(inset,size.y-inset-tape_h,size.x-inset*2,tape_h)
	nine(self,TexTape,tape,24.0,TAPE_BLEED,Color.WHITE if live else (Color(0.55,0.55,0.53) if disabled else Color(0.74,0.74,0.71)),true,true)
	# a long name (Juan Salvo's) in smaller letters, so that it fits the tape
	var tape_px: int = 21
	while tape_px > 14 and face("semi",2).get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,tape_px).x > tape.size.x-10.0: tape_px -= 1
	label(self,face("semi",2),text,size.x*0.5,tape.end.y-6,tape_px,INK)
