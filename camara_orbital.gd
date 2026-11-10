class_name CamaraOrbital
extends Node3D

# ======================================================================
#  camara_orbital.gd - Cámara orbital esférica interactiva + transiciones suaves
# ======================================================================

# ---------- AJUSTES ----------
var objetivo: Vector3 = Vector3(0.0, 1.2, 0.0)
var distancia: float = 14.0
var distancia_min: float = 3.0
var distancia_max: float = 40.0
var paso_zoom: float = 1.2
var sensibilidad: float = 0.005
var pitch_min: float = deg_to_rad(4.0)
var pitch_max: float = deg_to_rad(85.0)
var fov: float = 60.0
var lejos: float = 600.0

# ---------- MOVIMIENTO WASD ----------
var vel_por_metro: float = 0.5
var vel_min: float = 2.0
var vel_max: float = 20.0
var mult_shift: float = 3.0
var radio_mapa: float = 15.0
var altura_min: float = 0.3
var altura_max: float = 30.0

var depurar: bool = false
var bloqueo: Callable = Callable()

# ---------- MÁRGENES DE ENCUADRE (UI) ----------
var margen_izq: float = 0.0
var _margen_suave: float = 0.0
var margen_sup: float = 0.0          # Margen vertical superior
var _margen_sup_suave: float = 0.0   # Interpolación suave

# ---------- ESTADO ----------
var camara: Camera3D
var yaw: float = deg_to_rad(-40.0)
var pitch: float = deg_to_rad(25.0)
var _arrastrando: bool = false
var _teclas: Dictionary = {}
var _objetivo_inicial: Vector3
var _tween_cam: Tween = null


func _ready() -> void:
	_objetivo_inicial = objetivo
	camara = Camera3D.new()
	camara.name = "Camara"
	camara.fov = fov
	camara.far = lejos
	add_child(camara)
	camara.make_current()
	_actualizar()


func _actualizar() -> void:
	if camara == null:
		return
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	) * distancia
	camara.position = objetivo + offset
	camara.look_at(objetivo, Vector3.UP)


func _sobre_interfaz(pos: Vector2) -> bool:
	if bloqueo.is_valid() and bloqueo.call(pos):
		return true
	return get_viewport().gui_get_hovered_control() != null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var rueda: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP \
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		var bloqueado := _sobre_interfaz(event.position)
		if depurar and rueda:
			var h := get_viewport().gui_get_hovered_control()
			print("[CAMARA] rueda en %s | bloqueada=%s | hover=%s" % [
				event.position, bloqueado, str(h.get_path()) if h else "ninguno"])
		if event.pressed and bloqueado:
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_arrastrando = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				distancia = clampf(distancia - paso_zoom, distancia_min, distancia_max)
				_actualizar()
			MOUSE_BUTTON_WHEEL_DOWN:
				distancia = clampf(distancia + paso_zoom, distancia_min, distancia_max)
				_actualizar()
	elif event is InputEventMouseMotion and _arrastrando:
		yaw -= event.relative.x * sensibilidad
		pitch = clampf(pitch + event.relative.y * sensibilidad, pitch_min, pitch_max)
		_actualizar()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.pressed:
		_teclas.erase(event.physical_keycode)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	match k.physical_keycode:
		KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E:
			_teclas[k.physical_keycode] = true
		KEY_R:
			if not k.echo:
				objetivo = _objetivo_inicial
				_actualizar()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_teclas.clear()
		_arrastrando = false


func _aplicar_margen(delta: float) -> void:
	if camara == null:
		return
	# Interpolación horizontal (paneles laterales)
	_margen_suave = lerpf(_margen_suave, margen_izq, clampf(delta * 10.0, 0.0, 1.0))
	if absf(_margen_suave - margen_izq) < 0.5:
		_margen_suave = margen_izq

	# Interpolación vertical (franja superior de clima)
	_margen_sup_suave = lerpf(_margen_sup_suave, margen_sup, clampf(delta * 10.0, 0.0, 1.0))
	if absf(_margen_sup_suave - margen_sup) < 0.5:
		_margen_sup_suave = margen_sup

	var vp := get_viewport().get_visible_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
		
	var ancho_vista := 2.0 * distancia * tan(deg_to_rad(camara.fov) * 0.5) * (vp.x / vp.y)
	var alto_vista := 2.0 * distancia * tan(deg_to_rad(camara.fov) * 0.5)

	# Desplaza el encuadre 3D: h_offset a la derecha si hay panel lateral, v_offset hacia abajo si hay franja superior
	camara.h_offset = -(_margen_suave * 0.5 / vp.x) * ancho_vista
	camara.v_offset = (_margen_sup_suave * 0.5 / vp.y) * alto_vista


func _process(delta: float) -> void:
	_aplicar_margen(delta)
	if _teclas.is_empty():
		return

	var vel := clampf(distancia * vel_por_metro, vel_min, vel_max)
	if Input.is_key_pressed(KEY_SHIFT):
		vel *= mult_shift

	var adelante := Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()
	var derecha := Vector3(cos(yaw), 0.0, -sin(yaw)).normalized()
	var mov := Vector3.ZERO

	if _teclas.get(KEY_W, false): mov += adelante
	if _teclas.get(KEY_S, false): mov -= adelante
	if _teclas.get(KEY_D, false): mov += derecha
	if _teclas.get(KEY_A, false): mov -= derecha
	if _teclas.get(KEY_E, false): mov += Vector3.UP
	if _teclas.get(KEY_Q, false): mov -= Vector3.UP

	if mov.length_squared() > 0.001:
		objetivo += mov.normalized() * vel * delta
		var radio_xz := Vector2(objetivo.x, objetivo.z).length()
		if radio_xz > radio_mapa:
			var dir_xz := Vector2(objetivo.x, objetivo.z).normalized() * radio_mapa
			objetivo.x = dir_xz.x
			objetivo.z = dir_xz.y
		objetivo.y = clampf(objetivo.y, altura_min, altura_max)
		_actualizar()


# ======================================================================
#  TRANSICIÓN CINEMATOGRÁFICA SUAVE DE CÁMARA
# ======================================================================
func transicion_a(nuevo_yaw_deg: float, nuevo_pitch_deg: float, nueva_distancia: float, nuevo_objetivo: Vector3, duracion: float = 1.1) -> void:
	if _tween_cam != null and _tween_cam.is_running():
		_tween_cam.kill()

	_arrastrando = false
	_teclas.clear()

	var rad_yaw: float = deg_to_rad(nuevo_yaw_deg)
	var rad_pitch: float = deg_to_rad(nuevo_pitch_deg)

	# Camino angular más corto
	var diff_yaw: float = wrapf(rad_yaw - yaw, -PI, PI)
	var yaw_final: float = yaw + diff_yaw

	_tween_cam = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween_cam.tween_property(self, "yaw", yaw_final, duracion)
	_tween_cam.tween_property(self, "pitch", rad_pitch, duracion)
	_tween_cam.tween_property(self, "distancia", nueva_distancia, duracion)
	_tween_cam.tween_property(self, "objetivo", nuevo_objetivo, duracion)
	
	_tween_cam.parallel().tween_method(func(_v: float): _actualizar(), 0.0, 1.0, duracion)
	_tween_cam.chain().tween_callback(func():
		yaw = wrapf(yaw, -PI, PI)
		_actualizar()
	)
