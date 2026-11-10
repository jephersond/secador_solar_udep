class_name Tema
extends RefCounted

# ======================================================================
#  tema.gd - TEMA OSCURO "cristal" (vidrio oscuro translúcido)
#  Se mantienen los NOMBRES de las constantes para no romper otros módulos:
#    TINTA  = color del texto principal
#    GRIS   = texto secundario
#    BORDE  = línea fina tenue
#    TARJETA / TARJETA_CLARA = fondos translúcidos
#  El fondo del panel (desenfoque + niebla) lo dibuja cristal.gd.
#  Depuración en consola: prefijo [TEMA]
# ======================================================================

const FONDO := Color(0.07, 0.07, 0.08)
const TINTA := Color(0.95, 0.94, 0.92)
const GRIS := Color(0.68, 0.66, 0.62)
const BORDE := Color(1, 1, 1, 0.14)
const VELO := Color(1, 1, 1)
const ACENTO := Color(1.0, 0.416, 0.0)
const ACENTO_TEXTO := Color(1.0, 0.58, 0.25)
const ACENTO_FONDO := Color(1.0, 0.416, 0.0, 0.22)
const TEXTO_SOBRE_ACENTO := Color(0.09, 0.08, 0.07)
const TARJETA := Color(1, 1, 1, 0.07)
const TARJETA_CLARA := Color(1, 1, 1, 0.05)
const OK := Color(0.30, 0.76, 0.48)
const MAL := Color(1.0, 0.42, 0.37)
const AVISO := Color(0.94, 0.63, 0.13)
const TRANSP := Color(0, 0, 0, 0)
const RUTA_FUENTE := "res://fuentes/Inter-Regular.ttf"
const PILDORA := 99          # radio grande = esquinas totalmente redondas


static func caja(fondo: Color, borde: Color = BORDE, ancho: int = 1, margen: float = 8.0, radio: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = borde
	s.set_border_width_all(ancho)
	s.set_corner_radius_all(radio)
	s.set_content_margin_all(margen)
	return s


static func claro(c: Color) -> Color:
	return c.lightened(0.6) if c.get_luminance() < 0.25 else c


static func fuente() -> Font:
	var sistema := SystemFont.new()
	sistema.font_names = PackedStringArray(["Inter", "Segoe UI", "Arial", "sans-serif"])
	var base: Font = sistema
	if ResourceLoader.exists(RUTA_FUENTE):
		var ff = load(RUTA_FUENTE)
		ff.fallbacks = [sistema]
		base = ff
	else:
		print("[TEMA] no encuentro ", RUTA_FUENTE, ", uso fuente del sistema")
	var v := FontVariation.new()
	v.base_font = base
	v.opentype_features = {"tnum": 1}      # cifras tabulares
	return v


static func _casilla(marcuna: bool) -> ImageTexture:
	var n := 14
	var im := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	im.fill(Color(1, 1, 1, 0.10))
	for i in n:
		for c in [0, n - 1]:
			im.set_pixel(i, c, Color(VELO, 0.45))
			im.set_pixel(c, i, Color(VELO, 0.45))
	if marcuna:
		for y in range(3, n - 3):
			for x in range(3, n - 3):
				im.set_pixel(x, y, ACENTO)
	return ImageTexture.create_from_image(im)


static func _perilla() -> ImageTexture:
	var n := 14
	var im := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) / 2.0
	for y in n:
		for x in n:
			if Vector2(x, y).distance_to(Vector2(c, c)) <= 6.0:
				im.set_pixel(x, y, ACENTO)
	return ImageTexture.create_from_image(im)


static func _flecha() -> ImageTexture:
	var im := Image.create_empty(10, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in range(y, 10 - y):
			im.set_pixel(x, y, TINTA)
	return ImageTexture.create_from_image(im)


static func crear() -> Theme:
	var t := Theme.new()
	t.default_font = fuente()
	t.default_font_size = 13
	var vacio := StyleBoxEmpty.new()

	t.set_color("font_color", "Label", TINTA)
	# tarjeta por defecto (los paneles principales la reemplazan por vidrio)
	t.set_stylebox("panel", "PanelContainer", caja(TARJETA, BORDE, 1, 10.0, 14))

	# --- botones en pildora: normal tenue, hover con borde naranja, activo relleno ---
	for tipo in ["Button", "OptionButton"]:
		var n := caja(Color(1, 1, 1, 0.08), BORDE, 1, 5.0, PILDORA)
		n.content_margin_left = 14
		n.content_margin_right = 14
		var h := caja(Color(1, 1, 1, 0.16), ACENTO, 1, 5.0, PILDORA)
		h.content_margin_left = 14
		h.content_margin_right = 14
		var p := caja(ACENTO, ACENTO, 1, 5.0, PILDORA)
		p.content_margin_left = 14
		p.content_margin_right = 14
		t.set_stylebox("normal", tipo, n)
		t.set_stylebox("hover", tipo, h)
		t.set_stylebox("pressed", tipo, p)
		t.set_stylebox("hover_pressed", tipo, p)
		t.set_stylebox("disabled", tipo, n)
		t.set_stylebox("focus", tipo, vacio)
		for c in ["font_color", "font_hover_color", "font_focus_color"]:
			t.set_color(c, tipo, TINTA)
		for c in ["font_pressed_color", "font_hover_pressed_color"]:
			t.set_color(c, tipo, TEXTO_SOBRE_ACENTO)
		t.set_color("font_disabled_color", tipo, GRIS)
	t.set_icon("arrow", "OptionButton", _flecha())

	# --- casillas ---
	for e in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(e, "CheckBox", vacio)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckBox", TINTA)
	t.set_icon("checked", "CheckBox", _casilla(true))
	t.set_icon("unchecked", "CheckBox", _casilla(false))
	t.set_icon("checked_disabled", "CheckBox", _casilla(true))
	t.set_icon("unchecked_disabled", "CheckBox", _casilla(false))
	t.set_constant("h_separation", "CheckBox", 6)

	# --- menu desplegable ---
	t.set_stylebox("panel", "PopupMenu", caja(Color(0.10, 0.10, 0.11, 0.96), BORDE, 1, 6.0, 12))
	t.set_stylebox("hover", "PopupMenu", caja(ACENTO_FONDO, TRANSP, 0, 3.0, 8))
	t.set_color("font_color", "PopupMenu", TINTA)
	t.set_color("font_hover_color", "PopupMenu", TINTA)

	# --- pestanas (por si se vuelve a mostrar la barra de pestanas) ---
	var ts := caja(Color(1, 1, 1, 0.14), TRANSP, 0, 4.0, PILDORA)
	ts.content_margin_left = 12
	ts.content_margin_right = 12
	var tu := caja(TRANSP, TRANSP, 0, 4.0, PILDORA)
	tu.content_margin_left = 12
	tu.content_margin_right = 12
	var th := caja(Color(1, 1, 1, 0.08), TRANSP, 0, 4.0, PILDORA)
	th.content_margin_left = 12
	th.content_margin_right = 12
	t.set_stylebox("tab_selected", "TabContainer", ts)
	t.set_stylebox("tab_unselected", "TabContainer", tu)
	t.set_stylebox("tab_hovered", "TabContainer", th)
	t.set_stylebox("tab_disabled", "TabContainer", tu)
	t.set_stylebox("tab_focus", "TabContainer", vacio)
	var pv := StyleBoxEmpty.new()
	pv.content_margin_top = 4
	t.set_stylebox("panel", "TabContainer", pv)
	t.set_color("font_selected_color", "TabContainer", TINTA)
	t.set_color("font_unselected_color", "TabContainer", GRIS)
	t.set_color("font_hovered_color", "TabContainer", TINTA)

	# --- tablas ---
	t.set_stylebox("panel", "Tree", vacio)
	t.set_stylebox("focus", "Tree", vacio)
	t.set_stylebox("selected", "Tree", caja(ACENTO_FONDO, TRANSP, 0, 2.0, 6))
	t.set_stylebox("selected_focus", "Tree", caja(ACENTO_FONDO, TRANSP, 0, 2.0, 6))
	t.set_stylebox("cursor", "Tree", caja(ACENTO_FONDO, TRANSP, 0, 2.0, 6))
	t.set_stylebox("cursor_unfocused", "Tree", caja(ACENTO_FONDO, TRANSP, 0, 2.0, 6))
	for e in ["title_button_normal", "title_button_hover", "title_button_pressed"]:
		t.set_stylebox(e, "Tree", caja(TRANSP, TRANSP, 0, 4.0))
	t.set_color("font_color", "Tree", TINTA)
	t.set_color("font_selected_color", "Tree", TINTA)
	t.set_color("title_button_color", "Tree", GRIS)
	t.set_color("guide_color", "Tree", BORDE)
	t.set_color("relationship_line_color", "Tree", BORDE)
	t.set_constant("v_separation", "Tree", 4)

	# --- barras de desplazamiento ---
	for tipo in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", tipo, caja(Color(VELO, 0.06), TRANSP, 0, 4.0, 6))
		t.set_stylebox("scroll_focus", tipo, caja(Color(VELO, 0.06), TRANSP, 0, 4.0, 6))
		t.set_stylebox("grabber", tipo, caja(Color(VELO, 0.30), TRANSP, 0, 4.0, 6))
		t.set_stylebox("grabber_highlight", tipo, caja(ACENTO, TRANSP, 0, 4.0, 6))
		t.set_stylebox("grabber_pressed", tipo, caja(ACENTO, TRANSP, 0, 4.0, 6))

	# --- deslizador ---
	t.set_stylebox("slider", "HSlider", caja(Color(VELO, 0.18), TRANSP, 0, 2.0, 4))
	t.set_stylebox("grabber_area", "HSlider", caja(ACENTO, TRANSP, 0, 2.0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", caja(ACENTO, TRANSP, 0, 2.0, 4))
	var pe := _perilla()
	t.set_icon("grabber", "HSlider", pe)
	t.set_icon("grabber_highlight", "HSlider", pe)
	t.set_icon("grabber_disabled", "HSlider", pe)
	return t


static func factor_noche(h: float) -> float:
	var amanecer := smoothstep(5.0, 6.5, h)
	var anochecer := smoothstep(17.5, 19.0, h)
	return 1.0 - amanecer * (1.0 - anochecer)
