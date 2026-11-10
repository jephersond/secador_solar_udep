class_name EnlacePython
extends Node

# ======================================================================
#  enlace_python.gd - UDP (Python -> Godot) y control seguro del proceso
# ======================================================================

signal datos_recibidos(datos: Dictionary)

const PUERTO_UDP: int = 5005
var fecha_clima: String = ""
var hora_clima: float = 12.0
var duracion_clima: float = 2.0
var _udp := PacketPeerUDP.new()
var _pid_python: int = -1


func _ready() -> void:
	_iniciar_udp()
	_iniciar_python()


func _process(_delta: float) -> void:
	while _udp.get_available_packet_count() > 0:
		var texto := _udp.get_packet().get_string_from_utf8()
		var datos = JSON.parse_string(texto)
		if typeof(datos) == TYPE_DICTIONARY:
			datos_recibidos.emit(datos)


func _iniciar_udp() -> void:
	var err := _udp.bind(PUERTO_UDP, "127.0.0.1")
	if err != OK:
		push_warning("[UDP] No se pudo abrir el puerto %d (error %d)" % [PUERTO_UDP, err])
	else:
		print("[UDP] Escuchando en el puerto ", PUERTO_UDP)


func _iniciar_python() -> void:
	detener_python()

	var carpeta: String
	if OS.has_feature("editor"):
		carpeta = ProjectSettings.globalize_path("res://")
	else:
		carpeta = OS.get_executable_path().get_base_dir()
	var script := carpeta.path_join("clima_udp.py")
	if not FileAccess.file_exists(script):
		push_warning("[PYTHON] No encuentro clima_udp.py en: " + carpeta)
		return

	var args := PackedStringArray([script])
	if fecha_clima != "":
		args.append_array(["--fecha", fecha_clima, "--hora", str(hora_clima), "--duracion", str(duracion_clima)])

	_pid_python = OS.create_process("python", args, false)
	if _pid_python <= 0:
		_pid_python = OS.create_process("py", args, false)
	if _pid_python <= 0:
		push_warning("[PYTHON] No se pudo lanzar Python. ¿Está instalado y en el PATH?")
	else:
		print("[PYTHON] Lanzado proceso hijo (PID %d)" % _pid_python)


func pedir_clima(fecha: String, hora: float, duracion: float = 2.0) -> void:
	if _pid_python > 0 and fecha == fecha_clima and (fecha == "" or int(hora) == int(hora_clima)):
		return
	fecha_clima = fecha
	hora_clima = hora
	duracion_clima = duracion
	_iniciar_python()
	print("[CLIMA] Pidiendo clima de %s a las %.1f h" % [fecha if fecha != "" else "AHORA", hora])


# Cierra ÚNICAMENTE el proceso de Python lanzado por Godot (sin afectar otros programas)
func detener_python() -> void:
	if _pid_python > 0:
		var err := OS.kill(_pid_python)
		if err != OK and OS.get_name() == "Windows":
			OS.execute("taskkill", ["/F", "/PID", str(_pid_python), "/T"])
		_pid_python = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		detener_python()


func _exit_tree() -> void:
	detener_python()
	_udp.close()
