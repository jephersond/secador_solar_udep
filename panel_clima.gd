class_name PanelClima
extends CanvasLayer

# ======================================================================
#  panel_clima.gd - Widget de clima y franja superior en cristal translúcido
# ======================================================================

const ANCHO: float = 276.0
const MARGEN: float = 12.0
const ABIERTO_AL_INICIAR: bool = false

var clima: Clima
var datos: DatosSensores
var suelo: SueloMojado
var exterior: ClimaExterior
var interfaz: CanvasLayer = null

var _raiz: Control
var _tarjeta: PanelContainer
var _cr: Cristal
var _cr_franja: Cristal
var _icono: IconoClima
var _l_hora: Label
var _l_cond: Label
var _btn: BotonChevron
var _detalle: VBoxContainer
var _v_nubes: Label
var _v_lluvia: Label
var _v_suelo: Label

# Franja horizontal superior extendida
var _franja_exterior: PanelContainer
var _v_temp: Label
var _v_hr: Label
var _v_viento: Label
var _v_rad: Label
var _v_pres: Label

var _l_fuente: Label
var _c_auto: Chip
var _c_manual: Chip
var _c_reg: Chip
var _c_pc: Chip
var _c_sol: Chip
var _c_nub: Chip
var _c_llu: Chip
var _fila_man: HBoxContainer
var _clave_modo: String = ""
var _acum: float = 0.0


func _ready() -> void:
	layer = 11
	if clima == null:
		push_error("[PANEL_CLIMA] Falta asignar 'clima' antes de add_child")
		return
	_construir()
	_poner_abierto(ABIERTO_AL_INICIAR)
	_actualizar()
	print("[PANEL_CLIMA] Listo")


func _process(delta: float) -> void:
	if clima == null or _tarjeta == null:
		return
	_acum += delta
	if _acum >= 0.2:
		_acum = 0.0
		_actualizar()


func bloquea_mouse(pos: Vector2) -> bool:
	if not visible:
		return false
	var sobre_tarjeta: bool = _tarjeta != null and _tarjeta.is_visible_in_tree() and _tarjeta.get_global_rect().has_point(pos)
	var sobre_franja: bool = _franja_exterior != null and _franja_exterior.is_visible_in_tree() and _franja_exterior.get_global_rect().has_point(pos)
	return sobre_tarjeta or sobre_franja


func _construir() -> void:
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.theme = Tema.crear()
	add_child(_raiz)

	# -------------------------------------------------------------
	# 1. FRANJA HORIZONTAL SUPERIOR (Fondo de cristal puro)
	# -------------------------------------------------------------
	_franja_exterior = PanelContainer.new()
	_franja_exterior.anchor_left = 0.0
	_franja_exterior.anchor_right = 1.0
	_franja_exterior.anchor_top = 0.0
	_franja_exterior.anchor_bottom = 0.0
	_franja_exterior.offset_left = 74.0
	_franja_exterior.offset_right = -(ANCHO + MARGEN + 14.0)
	_franja_exterior.offset_top = 10.0
	_franja_exterior.offset_bottom = 106.0
	_franja_exterior.visible = false

	# El panel en sí es 100% transparente para que el shader Cristal dibuje el vidrio
	var st_franja := Tema.caja(Tema.TRANSP, Tema.TRANSP, 0, 18.0)
	st_franja.content_margin_left = 16.0
	st_franja.content_margin_right = 16.0
	st_franja.content_margin_top = 8.0
	st_franja.content_margin_bottom = 8.0
	_franja_exterior.add_theme_stylebox_override("panel", st_franja)
	_raiz.add_child(_franja_exterior)

	# Capa de cristal idéntica a las tarjetas del visor
	_cr_franja = Cristal.detras_de(_franja_exterior, 24.0, 16.0)
	_cr_franja.ligero = true
	_cr_franja.borde_alfa = 0.85
	_cr_franja.aplicar()

	var col_ext := VBoxContainer.new()
	col_ext.add_theme_constant_override("separation", 6)
	_franja_exterior.add_child(col_ext)

	var cap_ext := Label.new()
	cap_ext.text = "Exterior · Piura (estimado, Open - Meteo)"
	cap_ext.add_theme_font_size_override("font_size", 11)
	cap_ext.add_theme_color_override("font_color", Tema.GRIS)
	col_ext.add_child(cap_ext)

	var fila_metricas := HBoxContainer.new()
	fila_metricas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila_metricas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fila_metricas.add_theme_constant_override("separation", 8)
	col_ext.add_child(fila_metricas)

	_v_temp = _tile(fila_metricas, "Temp.")
	_v_hr = _tile(fila_metricas, "HR")
	_v_viento = _tile(fila_metricas, "Viento")
	_v_rad = _tile(fila_metricas, "Radiación")
	_v_pres = _tile(fila_metricas, "Presión")

	# -------------------------------------------------------------
	# 2. TARJETA COMPACTA SUPERIOR DERECHA (Píldora / Clima)
	# -------------------------------------------------------------
	_tarjeta = PanelContainer.new()
	_tarjeta.anchor_left = 1.0
	_tarjeta.anchor_right = 1.0
	_tarjeta.anchor_top = 0.0
	_tarjeta.anchor_bottom = 0.0
	_tarjeta.offset_left = -(MARGEN + ANCHO)
	_tarjeta.offset_right = -MARGEN
	_tarjeta.offset_top = 10.0
	_tarjeta.offset_bottom = 10.0
	_tarjeta.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tarjeta.grow_vertical = Control.GROW_DIRECTION_END
	
	var st := Tema.caja(Tema.TRANSP, Tema.TRANSP, 0, 18.0)
	st.content_margin_top = 8.0
	st.content_margin_bottom = 8.0
	st.content_margin_left = 12.0
	st.content_margin_right = 12.0
	_tarjeta.add_theme_stylebox_override("panel", st)
	_tarjeta.custom_minimum_size.x = ANCHO
	
	var ancho_util: float = ANCHO - st.get_margin(SIDE_LEFT) - st.get_margin(SIDE_RIGHT)
	_raiz.add_child(_tarjeta)

	_cr = Cristal.detras_de(_tarjeta, 24.0, 16.0)
	_cr.ligero = true
	_cr.borde_alfa = 0.85
	_cr.aplicar()

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_tarjeta.add_child(col)

	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 10)
	col.add_child(cab)

	_icono = IconoClima.new()
	cab.add_child(_icono)

	var textos := VBoxContainer.new()
	textos.add_theme_constant_override("separation", 0)
	textos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	textos.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cab.add_child(textos)

	_l_hora = Label.new()
	_l_hora.add_theme_font_size_override("font_size", 24)
	textos.add_child(_l_hora)

	_l_cond = Label.new()
	_l_cond.add_theme_font_size_override("font_size", 12)
	_l_cond.add_theme_color_override("font_color", Tema.GRIS)
	textos.add_child(_l_cond)

	_btn = BotonChevron.new()
	_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_btn.pressed.connect(func(): _poner_abierto(not _detalle.visible))
	cab.add_child(_btn)

	_detalle = VBoxContainer.new()
	_detalle.add_theme_constant_override("separation", 8)
	col.add_child(_detalle)

	var linea := ColorRect.new()
	linea.color = Color(1.0, 1.0, 1.0, 0.12)
	linea.custom_minimum_size = Vector2(0, 1)
	_detalle.add_child(linea)

	var fila1 := HBoxContainer.new()
	fila1.add_theme_constant_override("separation", 6)
	_detalle.add_child(fila1)
	_v_nubes = _tile(fila1, "Nubes", 14)
	_v_lluvia = _tile(fila1, "Lluvia", 14)
	_v_suelo = _tile(fila1, "Suelo húm.", 14)

	_detalle.add_child(_cap("Origen del clima"))
	var fila_modo := HBoxContainer.new()
	fila_modo.add_theme_constant_override("separation", 5)
	_detalle.add_child(fila_modo)
	_c_auto = _chip(fila_modo, "Auto", func(): _ir_a(Clima.Modo.AUTO))
	_c_manual = _chip(fila_modo, "Manual", func(): _ir_a(Clima.Modo.MANUAL))
	_c_reg = _chip(fila_modo, "Registro", func(): _ir_a(Clima.Modo.REGISTRO))
	_c_pc = _chip(fila_modo, "PC", func(): _ir_a(Clima.Modo.PC))

	_fila_man = HBoxContainer.new()
	_fila_man.add_theme_constant_override("separation", 5)
	_detalle.add_child(_fila_man)
	_c_sol = _chip(_fila_man, "Soleado", func(): _elegir_clima("soleado"))
	_c_nub = _chip(_fila_man, "Nublado", func(): _elegir_clima("nublado"))
	_c_llu = _chip(_fila_man, "Lluvia", func(): _elegir_clima("lluvia"))

	_l_fuente = Label.new()
	_l_fuente.add_theme_font_size_override("font_size", 11)
	_l_fuente.add_theme_color_override("font_color", Tema.ACENTO_TEXTO)
	_l_fuente.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_fuente.custom_minimum_size.x = ancho_util
	_detalle.add_child(_l_fuente)

	var teclas := Label.new()
	teclas.text = "Atajos: [F] Auto  [P] PC  [G] Registro  [1][2][3] Clima  [N][M][T] Hora  [C] Ciclo  [,/.] ±1 h"
	teclas.add_theme_font_size_override("font_size", 9)
	teclas.add_theme_color_override("font_color", Tema.GRIS)
	teclas.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	teclas.custom_minimum_size.x = ancho_util
	_detalle.add_child(teclas)


func _tile(padre: HBoxContainer, titulo: String, tam_num: int = 18) -> Label:
	var t := PanelContainer.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Cuadro interno con estilo idéntico a las gráficas: sutilmente translúcido con borde tenue
	var sb := Tema.caja(Tema.TARJETA, Tema.BORDE, 1, 8.0, 12)
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	t.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	t.add_child(v)
	
	var a := Label.new()
	a.text = titulo
	a.add_theme_font_size_override("font_size", 10)
	a.add_theme_color_override("font_color", Tema.GRIS)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	
	var b := Label.new()
	b.text = "—"
	b.add_theme_font_size_override("font_size", tam_num)
	b.add_theme_color_override("font_color", Tema.TINTA)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)

	padre.add_child(t)
	return b


func _poner_abierto(abierto: bool) -> void:
	_detalle.visible = abierto
	_btn.abierto = abierto
	_btn.queue_redraw()
	
	if _franja_exterior != null:
		_franja_exterior.visible = abierto

	_notificar_interfaz(abierto)
	_reajustar_tarjeta()

	if abierto:
		_clave_modo = ""
		_actualizar()


func _reajustar_tarjeta() -> void:
	if _tarjeta == null or not is_inside_tree():
		return
	if not _detalle.visible:
		_tarjeta.size.y = 0
	_tarjeta.reset_size()
	await get_tree().process_frame
	if is_inside_tree() and _tarjeta != null:
		_tarjeta.reset_size()


func _notificar_interfaz(abierto: bool) -> void:
	var obj_interfaz: Node = interfaz
	if obj_interfaz == null and is_inside_tree():
		obj_interfaz = get_tree().root.find_child("Interfaz", true, false)
		
	if obj_interfaz != null and obj_interfaz.has_method("notificar_clima_desplegado"):
		obj_interfaz.notificar_clima_desplegado(abierto)


func alternar_pantalla_completa(mostrar: bool) -> void:
	visible = mostrar
	if not mostrar:
		if _detalle != null and _detalle.visible:
			_poner_abierto(false)
		if _franja_exterior != null:
			_franja_exterior.visible = false


func _tipo_clima() -> String:
	var noche: bool = clima.hora < 5.5 or clima.hora >= 18.5
	if clima.lluvia > 0.15: return "lluvia"
	if clima.nubes > 0.6: return "nublado"
	if noche: return "luna"
	if clima.nubes > 0.3: return "parcial"
	return "sol"


func _texto_clima(tipo: String) -> String:
	match tipo:
		"lluvia": return "Lluvia"
		"nublado": return "Nublado"
		"luna": return "Noche despejada"
		"parcial": return "Parc. nublado"
	return "Despejado"


func _actualizar() -> void:
	var h: float = clima.hora
	var fn: float = Tema.factor_noche(h)
	if _cr != null:
		_cr.noche(fn)
	if _cr_franja != null:
		_cr_franja.noche(fn)
	
	var hh: int = int(h)
	var mm: int = int((h - float(hh)) * 60.0)
	_l_hora.text = "%02d:%02d" % [hh, mm]
	
	var tipo: String = _tipo_clima()
	if _icono.tipo != tipo:
		_icono.tipo = tipo
		_icono.queue_redraw()
	_l_cond.text = _texto_clima(tipo)

	var fecha_reloj: String = clima.fecha_txt
	var t_ext: float = NAN
	var hr_ext: float = NAN
	var v_ext: float = NAN
	var rad_ext: float = NAN
	var pres_ext: float = NAN

	if exterior != null:
		t_ext = exterior.valor("temp", h, fecha_reloj)
		hr_ext = exterior.valor("hr", h, fecha_reloj)
		v_ext = exterior.valor("viento", h, fecha_reloj)
		rad_ext = exterior.valor("rad", h, fecha_reloj)
		pres_ext = exterior.valor("pres", h, fecha_reloj)

	if exterior != null:
		_v_temp.text = _fmt(t_ext, "%.1f °C")
		_v_hr.text = _fmt(hr_ext, "%.0f%%")
		_v_viento.text = _fmt(v_ext, "%.1f m/s")
		_v_rad.text = _fmt(rad_ext, "%.0f W/m²")
		_v_pres.text = _fmt(pres_ext, "%.0f hPa")
	else:
		for l: Label in [_v_temp, _v_hr, _v_viento, _v_rad, _v_pres]:
			l.text = "—"

	if not _detalle.visible:
		return
		
	_actualizar_modo()

	_v_nubes.text = "%d%%" % int(round(clima.nubes * 100.0))
	_v_lluvia.text = "%d%%" % int(round(clima.lluvia * 100.0))
	_v_suelo.text = ("%d%%" % int(round(suelo.humedad * 100.0))) if suelo != null else "—"

	var nota: String = ""
	if exterior == null or not exterior.hay_datos():
		nota = "\nExterior: sin datos (¿Python sin internet?)"
	elif is_nan(t_ext):
		nota = "\nExterior: sin datos de esta fecha/hora"

	var modo: String = "MANUAL"
	match clima.modo_actual:
		Clima.Modo.AUTO: modo = "AUTO"
		Clima.Modo.PC: modo = "PC (reloj de la computadora)"
		Clima.Modo.REGISTRO: modo = "REGISTRO"

	var fecha: String = fecha_reloj if fecha_reloj != "" else "—"
	if modo == "AUTO" and clima.en_fallback:
		modo = "AUTO (sin Python: soleado)"
	_l_fuente.text = "%s · %s%s" % [modo, fecha, nota]


func _fmt(v: float, formato: String) -> String:
	return "—" if is_nan(v) else (formato % v)


func _cap(texto: String) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", Tema.GRIS)
	return l


func _chip(padre: HBoxContainer, texto: String, fn: Callable) -> Chip:
	var c := Chip.new(texto)
	c.pressed.connect(fn)
	padre.add_child(c)
	return c


func _ir_a(m: int) -> void:
	clima.cambiar_modo(m)
	_clave_modo = ""
	_actualizar_modo()


func _elegir_clima(nombre: String) -> void:
	clima.fijar_clima(nombre)
	_clave_modo = ""


func _actualizar_modo() -> void:
	var modo: int = clima.modo_actual
	var hay_reg: bool = datos != null and datos.hay_datos()
	var tipo: int = 1
	if clima.lluvia > 0.5: tipo = 3
	elif clima.nubes > 0.5: tipo = 2

	var clave: String = "%d|%s|%d" % [modo, hay_reg, tipo]
	if clave == _clave_modo:
		return
	_clave_modo = clave
	
	_c_auto.activar(modo == Clima.Modo.AUTO)
	_c_manual.activar(modo == Clima.Modo.MANUAL)
	_c_reg.activar(modo == Clima.Modo.REGISTRO)
	_c_pc.activar(modo == Clima.Modo.PC)
	_c_reg.disabled = not hay_reg
	_c_reg.tooltip_text = "" if hay_reg else "No hay un registro cargado"
	
	_fila_man.visible = (modo == Clima.Modo.MANUAL)
	_c_sol.activar(tipo == 1)
	_c_nub.activar(tipo == 2)
	_c_llu.activar(tipo == 3)
	_reajustar_tarjeta()


# ======================================================================
#  Subcomponentes vectoriales
# ======================================================================
class IconoClima extends Control:
	var tipo: String = "sol"

	func _init() -> void:
		custom_minimum_size = Vector2(40, 40)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _sol(c: Vector2, r: float) -> void:
		var col := Color(1.0, 0.78, 0.25)
		draw_circle(c, r, col)
		for i: int in 8:
			var a: float = i * TAU / 8.0
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * (r + 3.0), c + d * (r + 6.0), col, 2.0, true)

	func _nube(c: Vector2, k: float, col: Color) -> void:
		draw_circle(c + Vector2(-7, 3) * k, 6.0 * k, col)
		draw_circle(c + Vector2(1, -2) * k, 9.0 * k, col)
		draw_circle(c + Vector2(8, 3) * k, 6.0 * k, col)
		draw_rect(Rect2(c + Vector2(-7, 3) * k, Vector2(15, 6) * k), col)

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		match tipo:
			"sol": _sol(c, 9.0)
			"parcial":
				_sol(c + Vector2(5, -6), 7.0)
				_nube(c + Vector2(-2, 3), 0.85, Color(0.62, 0.68, 0.78))
			"nublado":
				_nube(c, 1.0, Color(0.52, 0.58, 0.70))
			"lluvia":
				_nube(c + Vector2(0, -4), 0.9, Color(0.42, 0.48, 0.62))
				for dx: float in [-6.0, 0.0, 6.0]:
					draw_line(c + Vector2(dx, 6), c + Vector2(dx - 3, 13), Color(0.45, 0.70, 1.0), 2.0, true)
			"luna":
				draw_circle(c, 10.0, Color(0.55, 0.57, 0.68))
				draw_circle(c + Vector2(-2, -2), 2.2, Color(0.42, 0.44, 0.56))
				draw_circle(c + Vector2(3, 3), 1.6, Color(0.42, 0.44, 0.56))


class BotonChevron extends Button:
	var abierto: bool = false
	var _sb: StyleBoxFlat = Tema.caja(Color(1, 1, 1, 0.06), Tema.BORDE, 1, 0.0, 14)
	var _sb_hov: StyleBoxFlat = Tema.caja(Color(1, 1, 1, 0.16), Tema.ACENTO, 1, 0.0, 14)

	func _init() -> void:
		custom_minimum_size = Vector2(28, 28)
		focus_mode = Control.FOCUS_NONE
		flat = true
		tooltip_text = "Mostrar / ocultar detalles"
		for e: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(e, StyleBoxEmpty.new())

	func _draw() -> void:
		var hov: bool = is_hovered()
		draw_style_box(_sb_hov if hov else _sb, Rect2(Vector2.ZERO, size))
		var col: Color = Tema.TINTA if hov else Tema.GRIS
		var c: Vector2 = size * 0.5
		var s: float = 4.5
		var k: float = -1.0 if abierto else 1.0
		draw_polyline(PackedVector2Array([
			Vector2(c.x - s, c.y - k * s * 0.4),
			Vector2(c.x, c.y + k * s * 0.6),
			Vector2(c.x + s, c.y - k * s * 0.4)]), col, 1.6, true)


class Chip extends Button:
	var _on: StyleBoxFlat
	var _off: StyleBoxFlat
	var _hov: StyleBoxFlat

	func _init(texto: String) -> void:
		text = texto
		focus_mode = Control.FOCUS_NONE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, 24)
		add_theme_font_size_override("font_size", 9)
		_off = Tema.caja(Color(1, 1, 1, 0.06), Tema.BORDE, 1, 3.0, 8)
		_hov = Tema.caja(Color(1, 1, 1, 0.14), Tema.ACENTO, 1, 3.0, 8)
		_on = Tema.caja(Color(Tema.ACENTO.r, Tema.ACENTO.g, Tema.ACENTO.b, 0.28), Tema.ACENTO, 1, 3.0, 8)
		activar(false)

	func activar(v: bool) -> void:
		var base: StyleBoxFlat = _on if v else _off
		add_theme_stylebox_override("normal", base)
		add_theme_stylebox_override("pressed", base)
		add_theme_stylebox_override("hover", _on if v else _hov)
		add_theme_stylebox_override("hover_pressed", base)
		add_theme_stylebox_override("disabled", _off)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		add_theme_color_override("font_color", Tema.TINTA if v else Tema.GRIS)
		add_theme_color_override("font_hover_color", Tema.TINTA)
		add_theme_color_override("font_pressed_color", Tema.TINTA)
		add_theme_color_override("font_disabled_color", Color(Tema.VELO, 0.35))
