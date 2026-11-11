extends Node3D

# ======================================================================
#  SECADOR SOLAR UDEP - Escena Principal Ensamblada
# ======================================================================

const PIEZAS_SECADOR: Array[String] = [
	"estructura_tubos.glb",
	"cubierta_policarbonato.glb",
	"mallas_laterales.glb",
	"piso_concreto.glb",
	"bandeja_B1.glb", "bandeja_B2.glb", "bandeja_B3.glb",
	"bandeja_B4.glb", "bandeja_B5.glb", "bandeja_B6.glb",
	"puerta_1.glb", "puerta_2.glb",
	"extractores_par_1.glb", "extractores_par_2.glb",
	"sondas_anemometros.glb"
]

const PIEZAS_CARCASA: Array[String] = [
	"estructura_tubos",
	"mallas_laterales",
	"puerta_1",
	"puerta_2"
]

const PIEZAS_ENTORNO: Array[String] = [
	"entorno_terreno.glb",
	"entorno_arboles.glb",
	"entorno_edificios.glb"
]

var vineta_intensidad: float = 0.45

var secador: Node3D
var entorno: Node3D
var clima: Clima
var enlace: EnlacePython
var cam: CamaraOrbital
var cielo: Cielo
var lluvia: Lluvia
var sombras: SombrasNubes
var charcos: Charcos
var suelo: SueloMojado
var bruma: Bruma
var datos: DatosSensores
var enlace_datos: EnlaceDatos
var interfaz: Interfaz
var colores: ColoresBandejas
var vidrio: Vidrio
var terreno: Node = null
var panel_clima: PanelClima
var exterior: ClimaExterior

var _minuto_actual: float = 0.0
var _listo: bool = false

# --- Animación de extractores y puertas ---
var girar_extractores: bool = false
var _aspas: Array[Node3D] = []
var _hojas_puertas: Array[Dictionary] = []
var _puertas_abiertas: bool = false

# --- Variables de Cotas y Despiece ---
var _cotas: Node3D
var _rotulos_despiece_b2: Node3D
var _rotulos_despiece_secador: Node3D

var _pos0: Dictionary = {}
var _bandeja_pos0: Dictionary = {}

const DESPIECE: Dictionary = {
	"estructura_tubos": Vector3(0, 1.5, 0),
	"mallas_laterales": Vector3(0, 1.5, 0),
	"cubierta_policarbonato": Vector3(0, 2.5, 0),
	"puerta_1": Vector3(0, 0, -1.5),
	"puerta_2": Vector3(0, 0, 1.5),
	"extractores_par_1": Vector3(0, 2.5, 1.5),
	"extractores_par_2": Vector3(0, 2.5, 1.5),
}

func _ready() -> void:
	# 1. Modelos 3D
	secador = Node3D.new()
	secador.name = "Secador"
	secador.rotation_degrees.y = 90.0
	add_child(secador)

	entorno = Node3D.new()
	entorno.name = "Entorno"
	add_child(entorno)

	for archivo: String in PIEZAS_SECADOR:
		_cargar_pieza("res://modelos/" + archivo, secador)
		
	for archivo: String in PIEZAS_ENTORNO:
		var pieza: Node = _cargar_pieza("res://modelos/" + archivo, entorno)
		if archivo == "entorno_terreno.glb":
			terreno = pieza

	_configurar_extractores()
	_configurar_puertas()

	# 2. Módulos meteorológicos y de entorno
	clima = Clima.new()
	clima.name = "Clima"
	add_child(clima)

	cam = CamaraOrbital.new()
	cam.name = "CamaraOrbital"
	add_child(cam)

	cielo = Cielo.new()
	cielo.name = "Cielo"
	cielo.clima = clima
	add_child(cielo)

	lluvia = Lluvia.new()
	lluvia.name = "Lluvia"
	lluvia.clima = clima
	lluvia.camara = cam.camara
	add_child(lluvia)

	sombras = SombrasNubes.new()
	sombras.name = "SombrasNubes"
	add_child(sombras)

	charcos = Charcos.new()
	charcos.name = "Charcos"
	add_child(charcos)

	bruma = Bruma.new()
	bruma.name = "Bruma"
	bruma.clima = clima
	bruma.cielo = cielo
	bruma.terreno = terreno
	add_child(bruma)

	suelo = SueloMojado.new()
	suelo.name = "SueloMojado"
	add_child(suelo)
	suelo.aplicar_a(terreno)

	enlace = EnlacePython.new()
	enlace.name = "EnlacePython"
	enlace.datos_recibidos.connect(clima.recibir_datos)
	add_child(enlace)

	exterior = ClimaExterior.new()
	exterior.name = "ClimaExterior"
	exterior.clima = clima
	add_child(exterior)
	enlace.datos_recibidos.connect(exterior.recibir)

	# 3. Telemetría y enlace con puente de datos (puente_datos.py)
	datos = DatosSensores.new()
	add_child(datos)
	datos.datos_cargados.connect(_al_cargar_registro)
	datos.minuto_cambiado.connect(_al_minuto_registro)

	enlace_datos = EnlaceDatos.new()
	enlace_datos.name = "EnlaceDatos"
	enlace_datos.datos = datos
	add_child(enlace_datos)

	# Descomenta la siguiente línea si deseas probar el simulador de inmediato sin el panel de conexión:
	# enlace_datos.conectar("sim", {"velocidad": 10})

	clima.modo_cambiado.connect(_al_cambiar_modo)
	datos.modo_vivo_cambiado.connect(_al_modo_vivo)

	var ruta_inicial: String = datos.ultimo_registro()
	datos.cargar_csv(ruta_inicial if ruta_inicial != "" else "res://datos/Registro_60_min.txt")

	# 4. Interfaz y gráficos
	interfaz = Interfaz.new()
	interfaz.name = "Interfaz"
	interfaz.datos = datos
	add_child(interfaz)
	interfaz.asignar_camara(cam.camara)
	interfaz.asignar_clima(clima)
	interfaz.asignar_enlace(enlace_datos)    # <-- CAMBIO 1: Enlace asignado a la interfaz
	interfaz.accion_secador.connect(_al_accion_secador)
	interfaz.vista_cambiada.connect(_al_cambiar_vista_camara)

	colores = ColoresBandejas.new()
	colores.datos = datos
	colores.secador = secador
	add_child(colores)

	vidrio = Vidrio.new()
	vidrio.name = "Vidrio"
	vidrio.secador = secador
	add_child(vidrio)

	_crear_vineta()
	_crear_cotas()
	_crear_rotulos_despiece_b2()
	_crear_rotulos_despiece_secador()

	panel_clima = PanelClima.new()
	panel_clima.name = "PanelClima"
	panel_clima.clima = clima
	panel_clima.datos = datos
	panel_clima.suelo = suelo
	panel_clima.exterior = exterior
	panel_clima.interfaz = interfaz
	add_child(panel_clima)

	interfaz.panel_clima_ref = panel_clima

	cam.bloqueo = func(pos: Vector2) -> bool:
		return interfaz.bloquea_mouse(pos) or panel_clima.bloquea_mouse(pos)

	clima.cambiar_modo(Clima.Modo.AUTO)
	_listo = true
	print("[SISTEMA] Secador Solar UDEP completamente ensamblado.")

func _process(delta: float) -> void:
	if interfaz != null and cam != null:
		cam.margen_izq = interfaz.margen_izquierdo()
		cam.margen_sup = interfaz.margen_superior()

	var luz: float = Clima.calcular_luz_dia(clima.hora)
	sombras.actualizar(delta, clima.nubes, luz)
	charcos.actualizar(delta, clima.lluvia, clima.nubes, luz)
	suelo.actualizar(delta, clima.lluvia, clima.nubes, luz)

	if girar_extractores:
		var paso: float = delta * 18.0
		for a: Node3D in _aspas:
			a.rotate_object_local(Vector3.FORWARD, paso)


func _cargar_pieza(ruta: String, grupo_padre: Node3D) -> Node:
	if ResourceLoader.exists(ruta):
		var recurso = load(ruta)
		if recurso is PackedScene:
			var objeto: Node = recurso.instantiate()
			objeto.name = ruta.get_file().get_basename()
			_apagar_relieve_huerfano(objeto)
			grupo_padre.add_child(objeto)
			return objeto
	else:
		push_warning("[MODELOS] Archivo no encontrado: " + ruta)
	return null


func _apagar_relieve_huerfano(nodo: Node) -> void:
	if nodo is MeshInstance3D and nodo.mesh is ArrayMesh:
		var am := nodo.mesh as ArrayMesh
		for i: int in am.get_surface_count():
			var tiene_tangentes: bool = bool(am.surface_get_format(i) & Mesh.ARRAY_FORMAT_TANGENT)
			if not tiene_tangentes:
				var mat = nodo.get_active_material(i)
				if mat is BaseMaterial3D and mat.normal_enabled:
					mat.normal_enabled = false
	for h: Node in nodo.get_children():
		_apagar_relieve_huerfano(h)


func _crear_vineta() -> void:
	var capa := CanvasLayer.new()
	capa.name = "Vineta"
	capa.layer = 1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float intensidad = 0.45;
uniform float radio = 0.80;
void fragment() {
	float d = length((UV - 0.5) * vec2(1.0, 0.85));
	float v = smoothstep(radio * 0.5, radio, d);
	COLOR = vec4(0.0, 0.0, 0.0, v * intensidad);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("intensidad", vineta_intensidad)
	rect.material = m
	capa.add_child(rect)
	add_child(capa)


# ======================================================================
#  CONFIGURACIÓN DE EXTRACTORES Y PUERTAS
# ======================================================================
func _configurar_extractores() -> void:
	_aspas.clear()
	for nom: String in ["extractores_par_1", "extractores_par_2"]:
		var raiz := secador.get_node_or_null(nom)
		if raiz == null:
			continue
		var encontrados: Array[String] = []
		_buscar_aspas(raiz, encontrados)
		print("[EXTRACTORES] %s: encontrados %s" % [nom, str(encontrados)])


func _buscar_aspas(n: Node, lista_nombres: Array[String]) -> void:
	var nom := n.name.to_lower()
	var es_aspa := nom.contains("aspa") or nom.contains("blade") or nom.contains("helice") \
		or nom.contains("rotor") or nom.contains("fan") or nom.contains("propeller")
	if n is Node3D and es_aspa:
		_aspas.append(n as Node3D)
		lista_nombres.append(n.name)
	for h: Node in n.get_children():
		_buscar_aspas(h, lista_nombres)


func _recoger_mallas(n: Node, lista: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		lista.append(n as MeshInstance3D)
	for h: Node in n.get_children():
		_recoger_mallas(h, lista)


func _configurar_puertas() -> void:
	_hojas_puertas.clear()
	for nom: String in ["puerta_1", "puerta_2"]:
		var p := secador.get_node_or_null(nom) as Node3D
		if p == null:
			continue
		var mallas: Array[MeshInstance3D] = []
		_recoger_mallas(p, mallas)
		var inv: Transform3D = p.global_transform.affine_inverse()

		var cajas: Array[AABB] = []
		var total := AABB()
		for i: int in mallas.size():
			var bb: AABB = inv * mallas[i].global_transform * mallas[i].get_aabb()
			cajas.append(bb)
			total = bb if i == 0 else total.merge(bb)

		var eje: int = 0 if total.size.x >= total.size.z else 2
		var medio: float = total.get_center()[eje]
		var es_p1: bool = (nom == "puerta_1")

		for lado: int in [0, 1]:
			var pivote := Node3D.new()
			pivote.name = "Hoja_" + ("izq" if lado == 0 else "der")
			var borde: float = total.position[eje] if lado == 0 else total.end[eje]
			var pos := Vector3.ZERO
			pos[eje] = borde
			pos[2 if eje == 0 else 0] = total.get_center()[2 if eje == 0 else 0]
			p.add_child(pivote)
			pivote.position = pos
			for i: int in mallas.size():
				var es_izq: bool = cajas[i].get_center()[eje] < medio
				if es_izq == (lado == 0):
					mallas[i].reparent(pivote, true)

			var signo: float = 1.0 if (lado == 0) else -1.0
			if not es_p1:
				signo = -signo
			_hojas_puertas.append({"nodo": pivote, "signo": signo})
		print("[PUERTAS] %s: 2 hojas agrupadas, eje de ancho %d" % [nom, eje])


func _animar_puertas(abrir: bool) -> void:
	_puertas_abiertas = abrir
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for item: Dictionary in _hojas_puertas:
		var ang: float = deg_to_rad(105.0) * float(item["signo"]) if abrir else 0.0
		t.tween_property(item["nodo"], "rotation:y", ang, 0.8)


# ======================================================================
#  ACCIONES DEL RIEL Y VISTAS SUPERIORES
# ======================================================================
func _al_accion_secador(id: String, activa: bool) -> void:
	match id:
		"rotulos":
			if _rotulos_despiece_secador != null:
				_rotulos_despiece_secador.visible = false
				for h: Node in _rotulos_despiece_secador.get_children():
					if h is Node3D:
						h.visible = false
			if _rotulos_despiece_b2 != null:
				_rotulos_despiece_b2.visible = false
				for h: Node in _rotulos_despiece_b2.get_children():
					if h is Node3D:
						h.visible = false

		"techo":
			var ver_carcasa: bool = not activa
			if vidrio != null:
				vidrio.mostrar(ver_carcasa)
			if secador != null:
				for nombre: String in PIEZAS_CARCASA:
					var pieza := secador.get_node_or_null(nombre)
					if pieza != null:
						pieza.visible = ver_carcasa

		"extractores":
			girar_extractores = activa

		"puertas":
			_animar_puertas(activa)

		"cotas":
			if _cotas != null:
				_cotas.visible = activa

		"despiece":
			_despiece(activa)

		"despiece_bandeja":
			_despiece_bandeja(activa)


func _al_cambiar_vista_camara(id_vista: String) -> void:
	if cam == null or not cam.has_method("transicion_a"):
		return
	match id_vista:
		"planta":
			cam.transicion_a(90.0, 88.5, 11.0, Vector3(0.0, 1.2, 0.0), 1.1)

		"exterior":
			cam.transicion_a(-45.0, 22.0, 8.5, Vector3(0.0, 1.2, 0.0), 1.1)

		"bandejas":
			cam.transicion_a(0.0, 4.0, 2.2, Vector3(0.0, 1.25, 0.0), 1.1)


# ======================================================================
#  RÓTULOS DE DESPIECE Y COTAS
# ======================================================================
func _crear_etiqueta_badge(txt: String, pos: Vector3, padre: Node3D, escala: float = 0.0035) -> Node3D:
	var pivote := Node3D.new()
	pivote.position = pos
	padre.add_child(pivote)

	var num_letras: float = float(txt.length())
	var ancho: float = maxf(num_letras * 0.058 + 0.35, 0.9)
	var alto: float = 0.22

	var quad := QuadMesh.new()
	quad.size = Vector2(ancho, alto)

	var mat_fondo := StandardMaterial3D.new()
	mat_fondo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_fondo.albedo_color = Color(0.10, 0.12, 0.15, 0.90)
	mat_fondo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_fondo.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat_fondo.no_depth_test = true
	mat_fondo.render_priority = 1

	var fondo := MeshInstance3D.new()
	fondo.name = "Fondo"
	fondo.mesh = quad
	fondo.material_override = mat_fondo
	pivote.add_child(fondo)

	var l := Label3D.new()
	l.name = "Label"
	l.text = txt
	l.font_size = 28
	l.pixel_size = escala
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.render_priority = 2
	l.modulate = Color(0.98, 0.98, 0.98)
	l.outline_size = 4
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	pivote.add_child(l)

	return pivote


func _crear_rotulos_despiece_b2() -> void:
	_rotulos_despiece_b2 = Node3D.new()
	_rotulos_despiece_b2.name = "RotulosDespieceB2"
	_rotulos_despiece_b2.visible = false
	secador.add_child(_rotulos_despiece_b2)

	var bx: float = -1.48
	var bz: float = 0.0

	var datos_b2: Array[Array] = [
		["1 · Bandeja: ángulo A-36 50×50×3", 1.0 + 1.35 + 0.05],
		["2 · Malla PP diamante 5×5", 1.0 + 1.05 + 0.03],
		["3 · Platina A-36 3×50", 1.0 + 0.75 + 0.02],
		["7 · Soportes ×3: ángulo 25×25×3", 0.985 + 0.40],
		["5/6 · Uniones ×7: tubo 30×30×2", 0.5 + 0.12],
		["4 · Patas ×6: tubo 30×30×2", 0.45]
	]

	for item: Array in datos_b2:
		var badge := _crear_etiqueta_badge(item[0], Vector3(bx - 0.7, item[1], bz), _rotulos_despiece_b2, 0.0032)
		badge.visible = false


func _crear_rotulos_despiece_secador() -> void:
	_rotulos_despiece_secador = Node3D.new()
	_rotulos_despiece_secador.name = "RotulosDespieceSecador"
	_rotulos_despiece_secador.visible = false
	secador.add_child(_rotulos_despiece_secador)

	var etiquetas_secador: Array[Array] = [
		["Cubierta de policarbonato", Vector3(0.0, 3.034 + 2.7, 0.0)],
		["Estructura tubular y mallas", Vector3(-2.6, 2.0 + 1.6, 0.0)],
		["4 Extractores axiales OP-AC12", Vector3(0.0, 2.05 + 2.6, 2.895 + 1.8)],
		["Puerta 1 (Acceso)", Vector3(0.0, 1.2, -2.895 - 1.8)],
		["Puerta 2 (Descarga)", Vector3(1.6, 1.2, 2.895 + 1.6)],
		["Batería de 6 bandejas", Vector3(2.4, 1.3, 0.0)]
	]

	for item: Array in etiquetas_secador:
		var badge := _crear_etiqueta_badge(item[0], item[1], _rotulos_despiece_secador, 0.0038)
		badge.visible = false


func _crear_cotas() -> void:
	_cotas = Node3D.new()
	_cotas.visible = false
	secador.add_child(_cotas)
	var hw: float = 2.462
	var z0: float = -2.895
	var z1: float = 2.895
	_cota(Vector3(-hw, 0.02, z0), Vector3(hw, 0.02, z0), "4924 mm", Vector3(0, 0, -1.05))
	_cota(Vector3(hw, 0.02, z0), Vector3(hw, 0.02, z1), "5790 mm", Vector3(0.9, 0, 0))
	_cota(Vector3(0, 3.034, z0), Vector3(0, 0, z0), "3034 mm", Vector3(3.05, 0, 0))
	_cota(Vector3(-1.65, 1.9, z0), Vector3(1.65, 1.9, z0), "3300 mm (h = 1900)", Vector3(0, 0, -0.45))
	_cota(Vector3(-0.7, 0.02, z0), Vector3(0.7, 0.02, z0), "Puerta 1400 × 1892", Vector3(0, 0, -0.45))
	_cota(Vector3(-3.465, 0, -3.895), Vector3(3.465, 0, -3.895), "Piso 6930 mm", Vector3(0, 0, -0.35))
	_cota(Vector3(3.465, 0, -3.895), Vector3(3.465, 0, 3.895), "Piso 7790 mm", Vector3(0.35, 0, 0))
	_cota(Vector3(-0.98, 1.04, -0.955), Vector3(-0.98, 1.04, 0.955), "1910 mm", Vector3(0.25, 0, 0))
	_cota(Vector3(-1.98, 1.04, -0.955), Vector3(-0.98, 1.04, -0.955), "1000 mm", Vector3(0, 0, -0.25))
	_cota(Vector3(-0.98, 0, -0.955), Vector3(-0.98, 1.0, -0.955), "h = 1000 mm", Vector3(0.25, 0, -0.25))


func _cota(a: Vector3, b: Vector3, txt: String, o: Vector3) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for v: Vector3 in [a, a + o, b, b + o, a + o, b + o]:
		im.surface_add_vertex(v)
	im.surface_end()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("d9480f")
	mat.no_depth_test = true

	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	_cotas.add_child(mi)

	var l := Label3D.new()
	l.text = txt
	l.font_size = 30
	l.pixel_size = 0.0038
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.modulate = Color("ffd8a8")
	l.outline_size = 8
	l.outline_modulate = Color(0.12, 0.04, 0.0, 0.95)
	l.position = (a + b) / 2.0 + o
	_cotas.add_child(l)


# ======================================================================
#  VISTAS EXPLOSIONADAS
# ======================================================================
func _despiece(activar: bool) -> void:
	if activar:
		for nombre: String in PIEZAS_CARCASA:
			var p := secador.get_node_or_null(nombre)
			if p != null:
				p.visible = true
		if vidrio != null:
			vidrio.mostrar(true)
		for b: String in ["bandeja_B1", "bandeja_B2", "bandeja_B3", "bandeja_B4", "bandeja_B5", "bandeja_B6"]:
			var nodo_b := secador.get_node_or_null(b) as Node3D
			if nodo_b != null:
				nodo_b.visible = true
		if entorno != null:
			entorno.visible = true

		# Rótulos de despiece del secador (activación limpia)
		if _rotulos_despiece_secador != null:
			_rotulos_despiece_secador.visible = true
			for h: Node in _rotulos_despiece_secador.get_children():
				if h is Node3D:
					h.visible = true
		if _rotulos_despiece_b2 != null:
			_rotulos_despiece_b2.visible = false
			for h: Node in _rotulos_despiece_b2.get_children():
				if h is Node3D:
					h.visible = false

		if cam != null and cam.has_method("transicion_a"):
			cam.transicion_a(-45.0, 26.0, 12.5, Vector3(0.0, 1.6, 0.0), 1.1)
	else:
		# Desactivación total de los rótulos de despiece
		if _rotulos_despiece_secador != null:
			_rotulos_despiece_secador.visible = false
			for h: Node in _rotulos_despiece_secador.get_children():
				if h is Node3D:
					h.visible = false

		if cam != null and cam.has_method("transicion_a"):
			cam.transicion_a(-45.0, 22.0, 8.5, Vector3(0.0, 1.2, 0.0), 1.1)

	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for nombre: String in DESPIECE:
		var nodo := secador.get_node_or_null(nombre) as Node3D
		if nodo == null:
			continue
		if not _pos0.has(nombre):
			_pos0[nombre] = nodo.position
		var destino: Vector3 = _pos0[nombre] + (DESPIECE[nombre] if activar else Vector3.ZERO)
		t.tween_property(nodo, "position", destino, 0.9)


func _despiece_bandeja(activar: bool) -> void:
	var raiz := secador.get_node_or_null("bandeja_B2") as Node3D
	if raiz == null:
		return

	var mallas: Array[MeshInstance3D] = []
	_recoger_mallas(raiz, mallas)

	# 1. AISLAMIENTO: Ocultar techo, otras bandejas, extractores Y SONDAS FLOTANTES
	if vidrio != null:
		vidrio.mostrar(not activar)
	for nombre: String in PIEZAS_CARCASA:
		var p := secador.get_node_or_null(nombre)
		if p != null:
			p.visible = not activar
			
	for otra: String in [
		"bandeja_B1", "bandeja_B3", "bandeja_B4", "bandeja_B5", "bandeja_B6",
		"extractores_par_1", "extractores_par_2", "sondas_anemometros"
	]:
		var o := secador.get_node_or_null(otra) as Node3D
		if o != null:
			o.visible = not activar

	if _rotulos_despiece_b2 != null:
		_rotulos_despiece_b2.visible = activar
		for h: Node in _rotulos_despiece_b2.get_children():
			if h is Node3D:
				h.visible = activar

	if _rotulos_despiece_secador != null:
		_rotulos_despiece_secador.visible = false
		for h: Node in _rotulos_despiece_secador.get_children():
			if h is Node3D:
				h.visible = false

	# 2. CÁMARA CENTRADA DIRECTAMENTE EN LA BANDEJA 2 ELEVADA
	if cam != null and cam.has_method("transicion_a"):
		if activar:
			cam.transicion_a(42.0, 18.0, 4.4, Vector3(0.0, 1.25, 1.48), 1.1)
		else:
			cam.transicion_a(-45.0, 22.0, 8.5, Vector3(0.0, 1.2, 0.0), 1.1)

	# 3. Elevación de piezas de B2
	var inv: Transform3D = raiz.global_transform.affine_inverse()
	var y_min: float = INF
	var y_max: float = -INF
	var cajas: Array[AABB] = []
	for m: MeshInstance3D in mallas:
		var bb: AABB = inv * m.global_transform * m.get_aabb()
		cajas.append(bb)
		y_min = minf(y_min, bb.position.y)
		y_max = maxf(y_max, bb.end.y)

	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i: int in mallas.size():
		var m: MeshInstance3D = mallas[i]
		if not _bandeja_pos0.has(m):
			_bandeja_pos0[m] = m.global_position
		var capa: float = _capa_bandeja(m, cajas[i].get_center().y - y_min, y_max - y_min, cajas[i])
		var destino: Vector3 = _bandeja_pos0[m] + (Vector3(0, capa, 0) if activar else Vector3.ZERO)
		t.tween_property(m, "global_position", destino, 0.9)


func _capa_bandeja(m: MeshInstance3D, rel_y: float, alto_total: float, bb: AABB) -> float:
	var n: String = str(m.name).to_lower()
	if n.contains("borde"): return 1.35
	if n.contains("malla"): return 1.05
	if n.contains("marco"): return 0.75
	if n.contains("angulo") or n.contains("ángulo"): return 0.40
	if n.contains("travesano") or n.contains("union") or n.contains("unión"): return 0.12
	if n.contains("pata"): return 0.0
	
	if bb.size.y > 0.6: return 0.0
	if rel_y < 0.8: return 0.12
	if bb.size.y < 0.02 and bb.size.x * bb.size.z > 1.2: return 1.05
	if rel_y > alto_total - 0.04: return 1.35
	if rel_y > alto_total - 0.07: return 0.75
	return 0.40


# ======================================================================
#  EVENTOS DE REGISTRO Y CLIMA
# ======================================================================
func _al_cargar_registro(_info: Dictionary) -> void:
	_minuto_actual = 0.0
	var t: Dictionary = datos.instante(0.0)
	var dur_h: float = maxf(datos.duracion / 60.0, 1.0)
	if clima.modo_actual == Clima.Modo.REGISTRO:
		clima.fijar_instante(int(t["doy"]), float(t["hora"]), str(t["fecha"]))
		enlace.pedir_clima(str(t["iso"]), float(t["hora"]), dur_h)


func _al_minuto_registro(m: float) -> void:
	_minuto_actual = m
	if not datos.hay_datos():
		return

	# CAMBIO 2: Si estamos recibiendo lecturas en vivo, no forzar la fecha histórica
	if datos.en_vivo:
		return

	if _listo and clima.modo_actual != Clima.Modo.REGISTRO:
		clima.cambiar_modo(Clima.Modo.REGISTRO)

	if clima.modo_actual == Clima.Modo.REGISTRO:
		var t: Dictionary = datos.instante(m)
		clima.fijar_instante(int(t["doy"]), float(t["hora"]), str(t["fecha"]))


# En vivo el clima debe ser el real de ahora (Auto); al salir se vuelve a Registro
func _al_modo_vivo(activo: bool) -> void:
	if not _listo:
		return
	if activo:
		if clima.modo_actual != Clima.Modo.AUTO:
			clima.cambiar_modo(Clima.Modo.AUTO)
	elif clima.modo_actual != Clima.Modo.REGISTRO and datos.hay_datos():
		clima.cambiar_modo(Clima.Modo.REGISTRO)


func _al_cambiar_modo(nuevo_modo: int) -> void:
	match nuevo_modo:
		Clima.Modo.AUTO:
			enlace.pedir_clima("", 0.0)
		Clima.Modo.PC:
			pass
		Clima.Modo.REGISTRO:
			if datos.hay_datos():
				var t: Dictionary = datos.instante(_minuto_actual)
				var dur_h: float = maxf(datos.duracion / 60.0, 1.0)
				clima.fijar_instante(int(t["doy"]), float(t["hora"]), str(t["fecha"]))
				enlace.pedir_clima(str(t["iso"]), float(t["hora"]), dur_h)
			else:
				enlace.pedir_clima("2026-10-23", 9.5, 2.0)
		Clima.Modo.MANUAL:
			pass
