class_name EnlaceDatos
extends Node

# ======================================================================
#  enlace_datos.gd - Habla con el puente Python (puente_datos.py) por UDP
#  Recibe en 127.0.0.1:5006  |  Envia comandos a 127.0.0.1:5007
#  (el clima sigue aparte, en el puerto 5005)
# ======================================================================

signal estado_cambiado(info: Dictionary)      # estado, fuente, detalle, lecturas
signal fuentes_actualizadas(lista: Array)     # lo que detecto el puente
signal extractor_respuesta(linea: String)       # lo que contesta el ESP32 al control de extractores
signal aviso(texto: String, error: bool)      # mensajes del puente para mostrar al usuario

const PUERTO_RX := 5006
const PUERTO_TX := 5007
const SIN_LATIDO_S := 6.0                     # el puente manda estado cada ~2 s

var datos: DatosSensores                      # asignar desde principal.gd
var estado := "sin_puente"   # sin_puente | desconectado | buscando | online | error
var fuente := ""
var detalle := ""
var lecturas := 0
var fuentes: Array = []

var _udp := PacketPeerUDP.new()
var _ult_msg_ms := 0
var _pid_puente: int = -1
var _acum_ping: float = 0.0
var _ruta_previa: String = ""                 # registro que se veia antes de activar el modo en vivo
var _puente_lanzado: bool = false             # alguna vez se pudo lanzar el puente
var _ult_relanzo_ms: int = 0


func _ready() -> void:
	var err := _udp.bind(PUERTO_RX, "127.0.0.1")
	if err != OK:
		push_warning("[ENLACE] No pude abrir el puerto UDP %d (error %d)" % [PUERTO_RX, err])
		set_process(false)
		return
	_udp.set_dest_address("127.0.0.1", PUERTO_TX)
	_ult_msg_ms = Time.get_ticks_msec()

	_iniciar_puente_python()
	buscar()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		detener_puente_python()


func _exit_tree() -> void:
	detener_puente_python()
	_udp.close()


func _process(delta: float) -> void:
	# Mantiene vivo al watchdog de Python mandando una señal cada 1.5 segundos
	_acum_ping += delta
	if _acum_ping >= 1.5:
		_acum_ping = 0.0
		_cmd({"cmd": "ping"})

	while _udp.get_available_packet_count() > 0:
		var txt := _udp.get_packet().get_string_from_utf8()
		var m = JSON.parse_string(txt)
		if typeof(m) != TYPE_DICTIONARY:
			continue
		_ult_msg_ms = Time.get_ticks_msec()
		match str(m.get("tipo", "")):
			"datos":
				if estado == "online" and datos != null:
					datos.agregar_lectura(m)
			"enlace":
				_aplicar_estado(str(m.get("estado", "")), str(m.get("fuente", "")),
					str(m.get("detalle", "")), int(m.get("lecturas", 0)))
			"fuentes":
				fuentes = m.get("lista", [])
				fuentes_actualizadas.emit(fuentes)
			"aviso":
				aviso.emit(str(m.get("texto", "")), bool(m.get("error", false)))
			"archivo_listo":
				_al_archivo_listo(m)
			"extractores":
				extractor_respuesta.emit(str(m.get("linea", "")))

	# Si el puente deja de mandar latidos, lo damos por apagado
	if estado != "sin_puente" and (Time.get_ticks_msec() - _ult_msg_ms) / 1000.0 > SIN_LATIDO_S:
		_aplicar_estado("sin_puente", "", "", 0)

	# Si el proceso del puente murio, lo relanza (maximo una vez cada 10 s)
	if estado == "sin_puente" and _puente_lanzado and (_pid_puente <= 0 or not OS.is_process_running(_pid_puente)):
		var ahora := Time.get_ticks_msec()
		if ahora - _ult_relanzo_ms > 10000:
			_ult_relanzo_ms = ahora
			print("[ENLACE] El puente no responde: lo relanzo")
			_iniciar_puente_python()


# ----------------------------------------------------------------------
#  GESTIÓN DEL SUBPROCESO PYTHON
# ----------------------------------------------------------------------
func _iniciar_puente_python() -> void:
	detener_puente_python()
	
	var carpeta: String
	if OS.has_feature("editor"):
		carpeta = ProjectSettings.globalize_path("res://")
	else:
		carpeta = OS.get_executable_path().get_base_dir()
		
	var script := carpeta.path_join("puente_datos.py")
	if not FileAccess.file_exists(script):
		# Busca en carpeta superior si se ejecuta en subcarpetas
		script = carpeta.get_base_dir().path_join("puente_datos.py")
		if not FileAccess.file_exists(script):
			push_warning("[ENLACE] No encuentro puente_datos.py para autoarranque")
			return

	var args := PackedStringArray([script, "--registrar"])
	if datos != null:
		args.append_array(["--carpeta-registros", datos.carpeta_registros()])
	_pid_puente = OS.create_process("python", args, false)
	if _pid_puente <= 0:
		_pid_puente = OS.create_process("py", args, false)

	if _pid_puente > 0:
		_puente_lanzado = true
		print("[ENLACE] Puente Python lanzado en segundo plano (PID %d)" % _pid_puente)


func detener_puente_python() -> void:
	if _pid_puente > 0:
		if OS.is_process_running(_pid_puente):
			OS.kill(_pid_puente)
			if OS.get_name() == "Windows":
				OS.execute("taskkill", ["/F", "/PID", str(_pid_puente), "/T"])
		_pid_puente = -1


# ----------------------------------------------------------------------
#  ESTADOS Y EVENTOS
# ----------------------------------------------------------------------
func _aplicar_estado(nuevo: String, f: String, det: String, n: int) -> void:
	var antes := estado
	fuente = f
	detalle = det
	lecturas = n
	if nuevo != antes:
		estado = nuevo
		print("[ENLACE] %s -> %s %s %s" % [antes, nuevo, f, det])
		if datos != null:
			if nuevo == "online":
				if not datos.en_vivo:
					datos.iniciar_vivo()
			elif datos.en_vivo and (nuevo == "desconectado" or nuevo == "error" or nuevo == "sin_puente"):
				datos.terminar_vivo()
				# Si no llegó ningún dato (falló al conectar), se vuelve al registro que se veía
				if not datos.hay_datos():
					_restaurar_registro_previo()
	estado_cambiado.emit({"estado": estado, "fuente": fuente, "detalle": detalle, "lecturas": lecturas})


# ----------------------------------------------------------------------
#  COMANDOS (los usara el panel de conexion)
# ----------------------------------------------------------------------
func _cmd(d: Dictionary) -> void:
	_udp.put_packet(JSON.stringify(d).to_utf8_buffer())


# El puente convirtió un archivo (p. ej. de la SD del ESP32): se carga como cualquier registro
func _al_archivo_listo(m: Dictionary) -> void:
	if datos == null:
		return
	if datos.en_vivo:
		datos.terminar_vivo()
	datos.cargar_csv(str(m.get("ruta", "")))


func importar(id_fuente: String, params: Dictionary = {}) -> void:
	if estado == "online":
		desconectar()
	_cmd({"cmd": "importar", "fuente": id_fuente, "params": params})


func buscar() -> void:
	_cmd({"cmd": "buscar"})


func conectar(id_fuente: String, params: Dictionary = {}) -> void:
	_cmd({"cmd": "conectar", "fuente": id_fuente, "params": params})


# Activa el modo en vivo: la interfaz entra en vivo al instante (sensores "esperando datos")
# en vez de esperar al primer ciclo, y se recuerda el registro que se veia por si falla.
func activar_vivo(id_fuente: String, params: Dictionary = {}) -> void:
	if datos != null and not datos.en_vivo:
		var previa: String = datos.archivo
		if previa != "" and previa != "(en vivo)":
			_ruta_previa = previa
		datos.iniciar_vivo()
	conectar(id_fuente, params)


func _restaurar_registro_previo() -> void:
	if datos != null and _ruta_previa != "" and FileAccess.file_exists(_ruta_previa):
		datos.cargar_csv(_ruta_previa)


# Manda un comando de texto al ESP32 por el puente (ver PROTOCOLO_EXTRACTORES.md).
# Solo funciona con la conexion serial en vivo.
func enviar_extractor(linea: String) -> void:
	_cmd({"cmd": "extractor", "linea": linea})


# Avisa al puente de la carpeta donde guardar las sesiones en vivo
func enviar_carpeta(ruta: String) -> void:
	_cmd({"cmd": "carpeta", "ruta": ruta})


func desconectar() -> void:
	_cmd({"cmd": "desconectar"})


func cargar_csv_directo() -> void:
	if estado == "online":
		desconectar()
	if datos == null:
		return
	if datos.en_vivo:
		datos.terminar_vivo()

	# Usa la ruta de tus datos, con fallback automático si cambió de nombre
	var ruta := "res://datos/Registro_60_min.txt"
	if not FileAccess.file_exists(ruta):
		ruta = "res://registro_secado_simulado.csv"

	datos.cargar_csv(ruta)


# Nombre legible de una fuente (el que mandó el puente en la lista)
func nombre_de(id_fuente: String) -> String:
	for f: Dictionary in fuentes:
		if str(f.get("id", "")) == id_fuente:
			return str(f.get("nombre", id_fuente))
	return id_fuente
