class_name Sitio
extends VBoxContainer

# ======================================================================
#  sitio.gd - Pestana "Sitio" (version 2: mapa vectorial con zoom)
#  Calles y edificios de OpenStreetMap + los bloques del modelo 3D,
#  secador, arboles, vector solar, sombra del secador y marcador de la
#  camara 3D.
#
#  USO: lo crea interfaz.gd, no hay que tocar principal.gd.
#    var s := Sitio.new()
#    s.datos = datos          # antes de add_child
#    contenedor.add_child(s)
#    s.actualizar()           # cuando cambia el minuto o se carga un archivo
#  OPCIONAL (marcador de camara): s.camara = <Camera3D>
#
#  MARCO DEL MAPA (metros): x = este, y = SUR. NORTE ARRIBA (como Google).
#  El secador esta en (0, 0).
#  El modelo 3D (BLOQUES, ARBOLES, camara) esta girado GIRO_MODELO grados
#  respecto al norte verdadero; aqui se rota para encajar con el mapa.
#
#  Datos: res://datos/sitio_osm.json (generado del GeoJSON de OpenStreetMap)
#  Mouse sobre el mapa: rueda = zoom hacia el cursor, arrastrar = mover,
#  doble clic = recentrar en el secador.
#  Depuracion en consola: prefijo [SITIO]
# ======================================================================

const LAT := -5.170761
const LON := -80.637987
const TZ := -5.0
const URL_MAPS := "https://maps.app.goo.gl/QNR2SKLDKBVjvpB4A"

# Giro del modelo respecto al norte (grados, sentido horario).
# Estimado de los bordes de los edificios en la imagen satelital (15 a 21).
# Si el sol del mapa y el de la escena no coinciden, ajusta este valor.
const GIRO_MODELO := 18.0
const RUTA_OSM := "res://mapa/sitio_osm.json"
const ALTO_SECADOR := 2.8                 # para la sombra (m)

# Respaldo si no hay datos cargados: registro del 23/10/2026, 09:28:53
const DOY_DEFECTO := 296
const SEG_DEFECTO := 9 * 3600 + 28 * 60 + 53
const FECHA_DEFECTO := "23/10/2026"
const DIAS_ACUM := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
const PUNTOS := ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]

# Edificios del modelo (medidos de la imagen satelital, ~8 px/m, +-3 m), en el
# marco del MODELO: x = este, z = sur. w = ancho (x); d = fondo (z)
const BLOQUES := [
	{"n": "Invernadero", "inv": true, "x": 15.0, "z": 5.6, "w": 12.9, "d": 35.0},
	{"x": -1.0, "z": 11.0, "w": 7.1, "d": 11.6},
	{"x": 1.0, "z": 22.0, "w": 9.6, "d": 10.0},
	{"x": 16.9, "z": 39.4, "w": 18.5, "d": 12.5},
	{"x": 30.8, "z": 29.3, "w": 9.4, "d": 11.5},
	{"x": 18.8, "z": 29.0, "w": 8.5, "d": 8.0},
	{"x": 21.5, "z": -11.0, "w": 2.0, "d": 2.0},
	{"x": -2.6, "z": -8.0, "w": 2.5, "d": 2.5},
	{"n": "Policlínico UDEP", "x": 95.0, "z": -1.0, "w": 30.0, "d": 62.0},
	{"x": 118.0, "z": -24.0, "w": 26.0, "d": 24.0},
]

# Arboles de entorno_arboles.glb: [x, z, radio de copa] en el marco del MODELO
const ARBOLES := [
	[-10.3, 13.5, 4.6], [-20.1, 5.8, 5.9], [-6.0, 22.2, 2.65], [8.2, 26.1, 3.7],
	[-23.5, 17.4, 3.55], [25.3, -5.8, 2.7], [-14.2, -19.8, 3.05], [16.3, -23.9, 3.55],
	[-34.3, 0.5, 4.4], [33.6, 14.6, 4.85], [2.9, 38.6, 3.2], [-39.8, -16.2, 2.65],
	[40.1, -17.4, 3.95], [-26.7, 34.4, 4.15], [6.5, 1.5, 4.15],
]

var datos: DatosSensores
var camara: Camera3D = null
var clima: Clima = null
var _ult_seg: float = -1.0
var _ult_doy: int = -1

var osm_edif: Array = []
var osm_vias: Array = []
var osm_ok: bool = false

var _lienzo: Lienzo
var _el: float = 0.0
var _az: float = 0.0
var _lbl_fecha: Label
var _lbl_sol: Label
var _t_cam := Transform3D()


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_cargar_osm()

	# Contenedor principal responsive (hijo 0)
	var contenedor_principal := BoxContainer.new()
	contenedor_principal.vertical = true
	contenedor_principal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenedor_principal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contenedor_principal.add_theme_constant_override("separation", 12)
	add_child(contenedor_principal)

	# --- SECCIÓN 1: MAPA Y CONTROLES DE ZOOM ---
	var col_mapa := VBoxContainer.new()
	col_mapa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_mapa.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col_mapa.add_theme_constant_override("separation", 6)
	contenedor_principal.add_child(col_mapa)

	var tit := Label.new()
	tit.text = "Calles y edificios: OpenStreetMap. Bloques del modelo medidos de la imagen satelital (±3 m)."
	tit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tit.add_theme_font_size_override("font_size", 11)
	tit.add_theme_color_override("font_color", Tema.GRIS)
	col_mapa.add_child(tit)

	_lienzo = Lienzo.new(self)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 6)
	fila.add_child(_boton("Cerca", func(): _lienzo.ver(70.0)))
	fila.add_child(_boton("Campus", func(): _lienzo.ver(280.0)))
	fila.add_child(_boton("Zona", func(): _lienzo.ver(1200.0)))
	fila.add_child(_boton("Recentrar", func(): _lienzo.recentrar()))
	col_mapa.add_child(fila)

	col_mapa.add_child(_lienzo)

	# --- SECCIÓN 2: INFORMACIÓN Y DATOS ---
	var col_datos := VBoxContainer.new()
	col_datos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_datos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col_datos.add_theme_constant_override("separation", 8)
	contenedor_principal.add_child(col_datos)

	var b_maps := Button.new()
	b_maps.text = "Abrir ubicación en Google Maps"
	b_maps.focus_mode = Control.FOCUS_NONE
	b_maps.pressed.connect(func(): OS.shell_open(URL_MAPS))
	col_datos.add_child(b_maps)

	var rejilla := GridContainer.new()
	rejilla.columns = 2
	rejilla.add_theme_constant_override("h_separation", 12)
	rejilla.add_theme_constant_override("v_separation", 3)
	col_datos.add_child(rejilla)
	_fila(rejilla, "Ubicación", "%s, %s (campus UDEP, Piura)" % [LAT, LON])
	_fila(rejilla, "Orientación", "Norte arriba. El modelo 3D está girado %.0f° respecto al norte (estimado de la imagen satelital)" % GIRO_MODELO)
	_fila(rejilla, "Puerta 1", "Extremo oeste del modelo · entrada de aire")
	_fila(rejilla, "Puerta 2 / extractores", "Extremo este del modelo, hacia el invernadero · anemómetros ID15 e ID16")
	_fila(rejilla, "Tablero", "Junto a la Puerta 2, en un poste cerca de un algarrobo")
	_lbl_fecha = _fila(rejilla, "Fecha y hora", "-")
	_lbl_sol = _fila(rejilla, "Sol (calculado)", "-")

	var nota := Label.new()
	nota.text = "El sol y la sombra del mapa y el sol del cielo 3D usan la misma fecha, hora y posición solar real (latitud y longitud del secador). " \
		+ "Teclas: R = seguir el registro, P = hora de la PC."
	nota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nota.add_theme_font_size_override("font_size", 11)
	nota.add_theme_color_override("font_color", Tema.GRIS)
	col_datos.add_child(nota)

	actualizar()
	print("[SITIO] lista (OSM: %s, %d edificios, %d vías)" % [osm_ok, osm_edif.size(), osm_vias.size()])


func establecer_modo_amplio(amplio: bool) -> void:
	# El contenedor que tiene el mapa y la tabla de datos abajo
	for c in get_children():
		if c is BoxContainer:
			c.vertical = not amplio
			if amplio:
				c.add_theme_constant_override("separation", 24)
			else:
				c.add_theme_constant_override("separation", 12)


# El marcador de la camara 3D se redibuja solo cuando la camara se mueve
func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _lienzo == null:
		return
	# si el reloj unico cambio (registro, teclas o PC), refrescar sol y fecha
	if clima != null and (absf(clima.hora * 3600.0 - _ult_seg) > 1.0 or clima.doy != _ult_doy):
		actualizar()
	if camara == null or not is_instance_valid(camara):
		return
	var t := camara.global_transform
	if not t.is_equal_approx(_t_cam):
		_t_cam = t
		_lienzo.queue_redraw()


func _boton(texto: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	return b


func _fila(padre: GridContainer, clave: String, valor: String) -> Label:
	var k := Label.new()
	k.text = clave
	k.add_theme_font_size_override("font_size", 12)
	k.add_theme_color_override("font_color", Tema.GRIS)
	k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	padre.add_child(k)
	var v := Label.new()
	v.text = valor
	v.add_theme_font_size_override("font_size", 12)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size = Vector2(150, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padre.add_child(v)
	return v


# ======================================================================
#  DATOS DE OPENSTREETMAP
# ======================================================================
func _cargar_osm() -> void:
	if not FileAccess.file_exists(RUTA_OSM):
		print("[SITIO] no encuentro %s; dibujo solo los bloques del modelo" % RUTA_OSM)
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(RUTA_OSM))
	if typeof(j) != TYPE_DICTIONARY:
		print("[SITIO] no pude leer sitio_osm.json")
		return
	for e in j.get("edificios", []):
		var pts := _a_puntos(e["p"])
		osm_edif.append({
			"pts": pts, "caja": _caja(pts), "n": str(e.get("n", "")),
			"ok": Geometry2D.triangulate_polygon(pts).size() > 0})
	for v in j.get("vias", []):
		var pts := _a_puntos(v["p"])
		osm_vias.append({
			"pts": pts, "caja": _caja(pts), "t": str(v.get("t", "")), "n": str(v.get("n", ""))})
	osm_ok = true


func _a_puntos(arr: Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for p in arr:
		o.append(Vector2(float(p[0]), float(p[1])))
	return o


func _caja(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return Rect2(mn, mx - mn)


# ======================================================================
#  ACTUALIZACION (la llama interfaz.gd al mover el minuto o cargar datos)
# ======================================================================
func actualizar() -> void:
	if _lienzo == null:
		return
	var seg: float
	var doy: int
	var fecha: String
	var origen := ""
	if clima != null:
		seg = clima.hora * 3600.0
		doy = clima.doy
		fecha = clima.fecha_txt
		origen = " · registro" if clima.sigue_registro else " · reloj de la PC"
	else:
		var b := _base()
		var m: float = datos.minuto if datos != null else 0.0
		seg = float(b["seg0"]) + m * 60.0
		doy = int(b["doy"])
		fecha = str(b["fecha"])
	_ult_seg = seg
	_ult_doy = doy
	var q := posicion_sol(seg, doy)
	_el = q.x
	_az = q.y
	var t := int(round(seg)) % 86400
	_lbl_fecha.text = "%s · %02d:%02d:%02d (UTC−5)%s" % [
		fecha, floori(t / 3600.0), floori((t % 3600) / 60.0), t % 60, origen]
	_lbl_sol.text = "altura %.1f° · azimut %.0f° (%s)%s" % [
		_el, _az, PUNTOS[int(round(_az / 45.0)) % 8],
		"" if _el > 0.0 else " · bajo el horizonte"]
	_lienzo.queue_redraw()


# Devuelve {"doy": int, "seg0": float, "fecha": String} del inicio del registro.
func _base() -> Dictionary:
	var res := {"doy": DOY_DEFECTO, "seg0": float(SEG_DEFECTO), "fecha": FECHA_DEFECTO}
	if datos == null or not datos.hay_datos():
		return res
	var txt := datos.inicio_texto.strip_edges().replace(" ", "T")
	var d := Time.get_datetime_dict_from_datetime_string(txt, false)
	var y: int = int(d.get("year", 0))
	var mes: int = int(d.get("month", 0))
	var dia: int = int(d.get("day", 0))
	if y < 2000 or mes < 1 or mes > 12 or dia < 1:
		print("[SITIO] no pude leer la fecha de inicio_texto ('%s'), uso la del registro del 23/10" % datos.inicio_texto)
		return res
	var bisiesto := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
	var extra := 1 if (bisiesto and mes > 2) else 0
	res["doy"] = int(DIAS_ACUM[mes - 1]) + dia + extra
	res["seg0"] = float(int(d.get("hour", 0)) * 3600 + int(d.get("minute", 0)) * 60 + int(d.get("second", 0)))
	res["fecha"] = "%02d/%02d/%04d" % [dia, mes, y]
	return res


# Posicion solar (formulas de la NOAA, igual que el HTML original).
# seg = segundos desde las 00:00 hora local; doy = dia del ano.
# Devuelve Vector2(altura en grados, azimut en grados desde el norte hacia el este).
static func posicion_sol(seg: float, doy: int) -> Vector2:
	var h := seg / 3600.0
	var g := TAU / 365.0 * (float(doy - 1) + (h - 12.0) / 24.0)
	var eq := 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) \
		- 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))
	var de := 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) \
		+ 0.000907 * sin(2.0 * g) - 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)
	var tst := seg / 60.0 + eq + 4.0 * LON - 60.0 * TZ
	var ha := deg_to_rad(tst / 4.0 - 180.0)
	var la := deg_to_rad(LAT)
	var cz := sin(la) * sin(de) + cos(la) * cos(de) * cos(ha)
	var el := PI / 2.0 - acos(clampf(cz, -1.0, 1.0))
	var az_s := atan2(sin(ha), cos(ha) * sin(la) - tan(de) * cos(la))
	var az := fposmod(rad_to_deg(az_s) + 180.0, 360.0)
	return Vector2(rad_to_deg(el), az)


# ======================================================================
#  LIENZO: mapa con zoom y arrastre (metros -> pixeles)
# ======================================================================
class Lienzo extends Control:
	var s: Sitio
	var fuente: Font
	var centro := Vector2.ZERO          # punto del mapa (m) en el centro de la vista
	var zoom := 2.0                     # pixeles por metro
	var _arrastrando := false
	var _ancho_pendiente := 280.0       # ancho de vista (m) a aplicar cuando se conozca el tamano

	var c_fondo := Color.html("#f1efe9")
	var c_via_b := Color.html("#a9b6cc")
	var c_via_p := Color.html("#d6deea")
	var c_via_b2 := Color.html("#d0d6e0")
	var c_edif := Color.html("#e3e5e8")
	var c_edif_b := Color.html("#b5bac2")
	var c_blq := Color.html("#ecd9d9")
	var c_blq_b := Color.html("#c98a8a")
	var c_inv := Color.html("#dcefe0")
	var c_inv_b := Color.html("#9fc7ab")
	var c_inv_l := Color.html("#b7d8c0")
	var c_inv_t := Color.html("#3d6b4a")
	var c_rojo := Color.html("#ea4335")
	var c_nombre := Color.html("#dd3333")
	var c_via_t := Color.html("#6a7587")
	var c_sec := Color.html("#5f6368")
	var c_tinta := Color.html("#202124")
	var c_sol := Color.html("#ff6a00")
	var c_cam := Color.html("#1a73e8")


	func _init(p_sitio: Sitio) -> void:
		s = p_sitio
		clip_contents = true
		custom_minimum_size = Vector2(0, 380)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		resized.connect(queue_redraw)


	# ---- vista ----
	func ver(ancho_m: float) -> void:
		centro = Vector2.ZERO
		_ancho_pendiente = ancho_m
		queue_redraw()


	func recentrar() -> void:
		centro = Vector2.ZERO
		queue_redraw()


	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				_zoom_en(mb.position, 1.18)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				_zoom_en(mb.position, 1.0 / 1.18)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				_arrastrando = mb.pressed
				if mb.pressed and mb.double_click:
					recentrar()
				accept_event()
		elif e is InputEventMouseMotion and _arrastrando:
			centro -= (e as InputEventMouseMotion).relative / zoom
			queue_redraw()
			accept_event()


	# zoom manteniendo fijo el punto del mapa que esta bajo el cursor
	func _zoom_en(pos: Vector2, factor: float) -> void:
		var antes := _s2w(pos)
		zoom = clampf(zoom * factor, 0.18, 40.0)
		centro = antes - (pos - size * 0.5) / zoom
		queue_redraw()


	# ---- transformaciones ----
	func _w2s(p: Vector2) -> Vector2:
		return size * 0.5 + (p - centro) * zoom


	func _s2w(p: Vector2) -> Vector2:
		return centro + (p - size * 0.5) / zoom


	# marco del modelo (x este, z sur) -> marco del mapa (norte arriba)
	func _mw(x: float, z: float) -> Vector2:
		var a := deg_to_rad(Sitio.GIRO_MODELO)
		return Vector2(x * cos(a) - z * sin(a), x * sin(a) + z * cos(a))


	func _pts_s(pts: PackedVector2Array) -> PackedVector2Array:
		var o := PackedVector2Array()
		o.resize(pts.size())
		for i in pts.size():
			o[i] = _w2s(pts[i])
		return o


	func _txt(pos: Vector2, t: String, tam: int, col: Color, centrar: bool = false) -> void:
		if centrar:
			pos.x -= fuente.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x * 0.5
		draw_string_outline(fuente, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, 3, Color(1, 1, 1, 0.85))
		draw_string(fuente, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, col)


	# [ancho en m, zoom minimo para dibujarla, color del borde, color del relleno]
	func _estilo_via(t: String) -> Array:
		match t:
			"primary", "primary_link":
				return [14.0, 0.0, c_via_b, c_via_p]
			"secondary", "secondary_link":
				return [11.0, 0.0, c_via_b, c_via_p]
			"tertiary", "tertiary_link":
				return [9.0, 0.0, c_via_b, c_via_p]
			"residential":
				return [6.5, 0.25, c_via_b2, Color.WHITE]
			_:
				return [4.0, 0.55, c_via_b2, Color.WHITE]


	func _rect_modelo(x: float, z: float, w: float, d: float) -> PackedVector2Array:
		return PackedVector2Array([
			_mw(x - w / 2.0, z - d / 2.0), _mw(x + w / 2.0, z - d / 2.0),
			_mw(x + w / 2.0, z + d / 2.0), _mw(x - w / 2.0, z + d / 2.0)])


	func _poligono(pts_mundo: PackedVector2Array, relleno: Color, borde: Color, ancho: float = 1.0) -> void:
		var p := _pts_s(pts_mundo)
		draw_colored_polygon(p, relleno)
		var cerrado := p.duplicate()
		cerrado.append(p[0])
		draw_polyline(cerrado, borde, ancho, true)


	func _draw() -> void:
		if s == null:
			return
		if fuente == null:
			fuente = Tema.fuente()
		if _ancho_pendiente > 0.0 and size.x > 10.0:
			zoom = size.x / _ancho_pendiente
			_ancho_pendiente = 0.0
		draw_rect(Rect2(Vector2.ZERO, size), c_fondo)
		var vis := Rect2(_s2w(Vector2.ZERO), Vector2.ZERO).expand(_s2w(size)).grow(20.0 / zoom)

		# ---- calles de OpenStreetMap (primero los bordes, luego los rellenos) ----
		for pasada in 2:
			for v in s.osm_vias:
				var est: Array = _estilo_via(v["t"])
				var zmin: float = est[1]
				if zoom < zmin or not vis.intersects(v["caja"], true):
					continue
				var ancho: float = maxf(float(est[0]) * zoom, 1.4)
				var pts := _pts_s(v["pts"])
				if pasada == 0:
					draw_polyline(pts, est[2], ancho + 2.0, true)
				else:
					draw_polyline(pts, est[3], ancho, true)

		# nombres de las calles principales
		if zoom >= 0.5:
			var puestos := {}
			for v in s.osm_vias:
				var nombre: String = v["n"]
				if nombre == "" or puestos.has(nombre):
					continue
				if not (v["t"] in ["primary", "secondary", "tertiary"]):
					continue
				if not vis.intersects(v["caja"], true):
					continue
				var pts: PackedVector2Array = v["pts"]
				var q := _w2s(pts[pts.size() >> 1])
				if Rect2(Vector2.ZERO, size).has_point(q):
					puestos[nombre] = true
					_txt(q, nombre, 10, c_via_t, true)

		# ---- edificios de OpenStreetMap ----
		for e in s.osm_edif:
			if not vis.intersects(e["caja"], true):
				continue
			var p := _pts_s(e["pts"])
			if e["ok"]:
				draw_colored_polygon(p, c_edif)
			var cerrado := p.duplicate()
			cerrado.append(p[0])
			draw_polyline(cerrado, c_edif_b, 1.0, true)
			var nom: String = e["n"]
			if nom != "" and zoom >= 1.4:
				var c: Vector2 = (e["caja"] as Rect2).get_center()
				_txt(_w2s(c), nom, 10, c_via_t, true)

		# ---- bloques del modelo (giran GIRO_MODELO grados) ----
		for b in Sitio.BLOQUES:
			var inv: bool = b.get("inv", false)
			var rc := _rect_modelo(b["x"], b["z"], b["w"], b["d"])
			_poligono(rc, c_inv if inv else c_blq, c_inv_b if inv else c_blq_b, 1.2)
			if inv and zoom >= 2.5:
				var zz: float = b["z"] - b["d"] / 2.0 + 1.6
				while zz < b["z"] + b["d"] / 2.0:
					draw_line(_w2s(_mw(b["x"] - b["w"] / 2.0, zz)), _w2s(_mw(b["x"] + b["w"] / 2.0, zz)), c_inv_l, 1.0)
					zz += 1.6
			var nombre: String = b.get("n", "")
			if nombre != "" and zoom >= 0.8:
				var cc := _w2s(_mw(b["x"], b["z"]))
				_txt(cc, nombre, 11, c_inv_t if inv else c_nombre, true)

		# hospital
		var ph := _w2s(_mw(95.0, -8.0))
		draw_circle(ph, 8.0, c_rojo)
		_txt(ph + Vector2(0, 4), "H", 11, Color.WHITE, true)

		# ---- arboles (posiciones de entorno_arboles.glb) ----
		if zoom >= 0.9:
			for t in Sitio.ARBOLES:
				var pt := _w2s(_mw(t[0], t[1]))
				var r: float = float(t[2]) * zoom
				draw_circle(pt, r, Color(0.65, 0.82, 0.60, 0.70))
				draw_arc(pt, r, 0.0, TAU, 24, Color(0.45, 0.65, 0.42, 0.9), 1.0, true)

		# ---- sol: direccion y sombra del secador ----
		var az := deg_to_rad(s._az)
		var dir_sol := Vector2(sin(az), -cos(az))                 # hacia el sol (norte arriba)
		var secador := _rect_modelo(0.0, 0.0, 5.8, 4.92)
		if s._el > 1.5:
			var largo := minf(Sitio.ALTO_SECADOR / tan(deg_to_rad(s._el)), 40.0)
			var desp := -dir_sol * largo
			var todos := PackedVector2Array()
			for q in secador:
				todos.append(q)
				todos.append(q + desp)
			var casco := Geometry2D.convex_hull(todos)
			if casco.size() > 1 and casco[0] == casco[casco.size() - 1]:
				casco.resize(casco.size() - 1)
			if casco.size() >= 3:
				draw_colored_polygon(_pts_s(casco), Color(0, 0, 0, 0.22))

		# ---- secador (Puerta 1 al oeste del modelo: franja naranja) ----
		_poligono(secador, c_sec, c_tinta, 1.0)
		var franja := PackedVector2Array([
			_mw(-2.9, -2.46), _mw(-2.2, -2.46), _mw(-2.2, 2.46), _mw(-2.9, 2.46)])
		draw_colored_polygon(_pts_s(franja), c_sol)

		# ---- marcador de la camara 3D ----
		if s.camara != null and is_instance_valid(s.camara):
			var cp: Vector3 = s.camara.global_position
			var f: Vector3 = -s.camara.global_transform.basis.z
			var dv := _mw(f.x, f.z)
			var pc := _w2s(_mw(cp.x, cp.z))
			if dv.length() > 0.001:
				var ang := dv.angle()
				var cono := PackedVector2Array([
					pc,
					pc + Vector2.from_angle(ang - 0.5) * 32.0,
					pc + Vector2.from_angle(ang + 0.5) * 32.0])
				draw_colored_polygon(cono, Color(c_cam.r, c_cam.g, c_cam.b, 0.28))
			draw_circle(pc, 6.0, Color.WHITE)
			draw_circle(pc, 4.0, c_cam)

		# ---- chincheta roja sobre el secador (tamano fijo en pixeles) ----
		var p0 := _w2s(Vector2.ZERO)
		draw_colored_polygon(PackedVector2Array([
			p0, p0 + Vector2(-6.5, -15.0), p0 + Vector2(6.5, -15.0)]), c_rojo)
		draw_circle(p0 + Vector2(0, -21.0), 9.0, c_rojo)
		draw_circle(p0 + Vector2(0, -21.0), 3.5, Color.WHITE)
		_txt(p0 + Vector2(14, -22), "Secador", 11, c_tinta)

		# ---- vector solar (largo fijo en pixeles) ----
		var p1 := p0 + dir_sol * 95.0
		var col_sol := c_sol if s._el > 0.0 else Color(0.5, 0.5, 0.5)
		draw_dashed_line(p0, p1, col_sol, 2.0, 6.0)
		draw_circle(p1, 7.0, col_sol)
		_txt(p1 + Vector2(10, 4), "sol", 11, c_tinta)

		# ---- escala dinamica ----
		var pasos := [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0]
		var largo_m: float = 2000.0
		for pm in pasos:
			if float(pm) * zoom >= 70.0:
				largo_m = float(pm)
				break
		var ex := 14.0
		var ey := size.y - 22.0
		var lpx := largo_m * zoom
		draw_line(Vector2(ex, ey), Vector2(ex + lpx, ey), c_tinta, 2.0)
		draw_line(Vector2(ex, ey - 4), Vector2(ex, ey + 4), c_tinta, 2.0)
		draw_line(Vector2(ex + lpx, ey - 4), Vector2(ex + lpx, ey + 4), c_tinta, 2.0)
		var etq: String = "%d m" % int(largo_m) if largo_m < 1000.0 else "%d km" % int(largo_m / 1000.0)
		_txt(Vector2(ex, ey - 8), etq, 10, c_tinta)

		# ---- flecha del norte (el norte siempre esta arriba) ----
		var pn := Vector2(size.x - 28.0, 30.0)
		draw_circle(pn, 16.0, Color.WHITE)
		draw_arc(pn, 16.0, 0.0, TAU, 32, Color.html("#dadce0"), 1.0, true)
		draw_line(pn + Vector2(0, 9), pn + Vector2(0, -9), c_tinta, 1.5)
		draw_polyline(PackedVector2Array([
			pn + Vector2(-4, -4), pn + Vector2(0, -9), pn + Vector2(4, -4)]), c_tinta, 1.5)
		_txt(pn + Vector2(0, -20), "N", 10, c_tinta, true)

		# ---- ayuda y atribucion ----
		_txt(Vector2(8, 14), "Rueda: zoom · Arrastrar: mover · Doble clic: recentrar", 9, Color(0.4, 0.4, 0.4))
		var atrib: String = "© colaboradores de OpenStreetMap" if s.osm_ok else "Sin datos de OpenStreetMap (falta res://mapa/sitio_osm.json)"
		var w_atr := fuente.get_string_size(atrib, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		_txt(Vector2(size.x - w_atr - 8.0, size.y - 8.0), atrib, 9, Color(0.35, 0.35, 0.35))

		# ---- borde ----
		draw_rect(Rect2(Vector2.ZERO, size), Tema.BORDE, false, 1.0)
