class_name Cielo
extends Node3D

# ======================================================================
#  cielo.gd - Sol, luna, cielo dinámico y WorldEnvironment
# ======================================================================

var clima: Clima

# Parámetros de iluminación
var sol_energia: float = 1.4
var sol_color: Color = Color(1.0, 0.93, 0.80)
var sombra_suavidad: float = 1.6
var ambiente_energia: float = 1.0
var ssao_intensidad: float = 2.2
var exposicion: float = 1.0
var luna_energia: float = 0.35
var noche_brillo: float = 2.0

# Nodos y recursos públicos (bruma.gd los lee directamente)
var sol: DirectionalLight3D
var luna: DirectionalLight3D
var env: Environment
var mat_cielo: ShaderMaterial
var we: WorldEnvironment

var _acum_cielo: float = 0.0
var _tiempo_nubes: float = 0.0

# Shader con uniforms de bruma ya integrados nativamente
const CODIGO_CIELO = """
shader_type sky;

uniform vec3 sol_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 luna_dir = vec3(0.0, -1.0, 0.0);
uniform float dia = 1.0;
uniform float nubes = 0.0;
uniform float lluvia = 0.0;
uniform float tiempo = 0.0;
uniform vec3 bruma_color : source_color = vec3(0.86, 0.85, 0.82);
uniform float bruma = 0.0;

uniform vec3 dia_cenit : source_color = vec3(0.30, 0.52, 0.85);
uniform vec3 dia_horizonte : source_color = vec3(0.78, 0.84, 0.90);
uniform vec3 noche_cenit : source_color = vec3(0.010, 0.020, 0.070);
uniform vec3 noche_horizonte : source_color = vec3(0.050, 0.070, 0.150);
uniform vec3 suelo_color : source_color = vec3(0.55, 0.47, 0.38);
uniform vec3 gris_nublado : source_color = vec3(0.62, 0.65, 0.70);
uniform vec3 calido : source_color = vec3(1.0, 0.55, 0.25);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	float arriba = smoothstep(0.0, 0.6, h);
	float crep = 1.0 - abs(dia * 2.0 - 1.0);

	vec3 cen = mix(noche_cenit, dia_cenit, dia);
	vec3 hor = mix(noche_horizonte, dia_horizonte, dia);
	hor = mix(hor, calido, crep * 0.6 * (1.0 - lluvia));
	vec3 col = mix(hor, cen, arriba);

	vec3 gris = gris_nublado * mix(0.12, 1.0, dia);
	col = mix(col, gris, clamp(nubes * 0.85 + lluvia * 0.1, 0.0, 1.0));

	vec3 suelo = suelo_color * mix(0.05, 0.9, dia);
	col = mix(col, suelo, 1.0 - smoothstep(-0.08, 0.0, h));

	// Sol
	float sd = max(dot(d, normalize(sol_dir)), 0.0);
	float disco = smoothstep(0.9995, 0.9999, sd);
	float halo = pow(sd, 64.0) * 0.35;
	float vis_sol = dia * (1.0 - nubes * 0.9) * step(0.0, h);
	col += (vec3(1.0, 0.95, 0.8) * disco * 3.0 + vec3(1.0, 0.85, 0.6) * halo) * vis_sol;

	// Luna
	float md = max(dot(d, normalize(luna_dir)), 0.0);
	float noche_vis = (1.0 - dia) * (1.0 - nubes * 0.85) * step(0.0, h);
	col += vec3(0.85, 0.90, 1.0) * smoothstep(0.9990, 0.9994, md) * noche_vis * 1.5;
	col += vec3(0.30, 0.40, 0.70) * pow(md, 200.0) * 0.2 * noche_vis;

	// Estrellas
	vec3 sp = d * 220.0;
	vec3 celda = floor(sp);
	float r = hash3(celda);
	float estrella = step(0.9975, r);
	vec3 fr = fract(sp) - 0.5;
	estrella *= 1.0 - smoothstep(0.0, 0.35, length(fr));
	col += vec3(1.0) * estrella * (1.0 - dia) * (1.0 - nubes) * step(0.0, h) * 1.5;

	// Nubes
	float ch = max(h, 0.0) + 0.08;
	vec2 uv = d.xz / ch * 0.6 + vec2(tiempo * 0.02, tiempo * 0.008);
	float n = fbm(uv);
	float cobertura = mix(0.75, 0.25, nubes);
	float nube = smoothstep(cobertura, cobertura + 0.25, n) * smoothstep(0.0, 0.12, h);
	vec3 nube_luz = mix(vec3(0.25, 0.28, 0.35), vec3(1.0), dia);
	nube_luz = mix(nube_luz, nube_luz * 0.55, lluvia);
	nube_luz = mix(nube_luz, calido * 0.9, crep * 0.4 * (1.0 - nubes));
	col = mix(col, nube_luz * mix(1.0, 0.8, n), nube * (0.35 + 0.65 * nubes));

	// Franja de bruma en el horizonte (sin parches externos)
	col = mix(col, bruma_color, bruma * (1.0 - smoothstep(0.0, 0.35, h)));

	COLOR = col;
}
"""


func _ready() -> void:
	_configurar_sol()
	_configurar_luna()
	_configurar_ambiente()
	_aplicar_estado(true)


func _process(delta: float) -> void:
	_tiempo_nubes += delta
	_acum_cielo += delta
	var tocar_cielo := _acum_cielo >= 0.1
	if tocar_cielo:
		_acum_cielo = 0.0
	_aplicar_estado(tocar_cielo)


func _configurar_sol() -> void:
	sol = DirectionalLight3D.new()
	sol.name = "Sol"
	sol.light_color = sol_color
	sol.light_energy = sol_energia
	sol.shadow_enabled = true
	sol.shadow_blur = sombra_suavidad
	sol.light_angular_distance = 0.8
	sol.shadow_normal_bias = 1.0
	sol.shadow_bias = 0.05
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sol.directional_shadow_max_distance = 140.0
	add_child(sol)


func _configurar_luna() -> void:
	luna = DirectionalLight3D.new()
	luna.name = "Luna"
	luna.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	luna.light_color = Color(0.55, 0.65, 1.0)
	luna.light_energy = 0.0
	luna.shadow_enabled = true
	luna.shadow_blur = 2.0
	luna.directional_shadow_max_distance = 100.0
	luna.visible = false
	add_child(luna)


func _configurar_ambiente() -> void:
	var sh := Shader.new()
	sh.code = CODIGO_CIELO
	mat_cielo = ShaderMaterial.new()
	mat_cielo.shader = sh

	var sky := Sky.new()
	sky.sky_material = mat_cielo
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = ambiente_energia
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = exposicion
	env.tonemap_white = 6.0

	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = ssao_intensidad
	env.ssao_power = 1.6
	env.ssao_light_affect = 0.3

	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.03

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12

	we = WorldEnvironment.new()
	we.name = "Ambiente"
	we.environment = env
	add_child(we)


func _aplicar_estado(actualizar_cielo: bool) -> void:
	var h: float = clima.hora if clima else 12.0
	var n_val: float = clima.nubes if clima else 0.05
	var ll_val: float = clima.lluvia if clima else 0.0
	var doy: int = clima.doy if clima else 296

	var pos := Sitio.posicion_sol(h * 3600.0, doy)
	var elev := pos.x
	var az := 180.0 - pos.y + Sitio.GIRO_MODELO
	var dia := smoothstep(-6.0, 8.0, elev)

	sol.rotation_degrees = Vector3(-elev, az, 0.0)
	var luz_dia := smoothstep(0.0, 10.0, elev)
	var e_sol := sol_energia * luz_dia * (1.0 - 0.7 * n_val) * (1.0 - 0.2 * ll_val)
	sol.light_energy = e_sol
	sol.visible = e_sol > 0.01
	sol.light_color = sol_color.lerp(Color(1.0, 0.6, 0.35), 1.0 - smoothstep(0.0, 25.0, elev))
	sol.shadow_blur = lerpf(sombra_suavidad, 4.0, n_val)

	var e_luna := luna_energia * (1.0 - dia) * (1.0 - 0.7 * n_val)
	luna.light_energy = e_luna
	luna.visible = e_luna > 0.01

	# Ajustes globales de ambiente (dejando fog_* exclusivamente para bruma.gd)
	env.ambient_light_energy = ambiente_energia * lerpf(noche_brillo, 1.0, dia)
	env.tonemap_exposure = exposicion
	env.adjustment_saturation = lerpf(1.12, 0.85, n_val)
	env.adjustment_brightness = 1.0 - 0.06 * ll_val

	if actualizar_cielo and mat_cielo:
		mat_cielo.set_shader_parameter("sol_dir", sol.basis.z)
		mat_cielo.set_shader_parameter("luna_dir", luna.basis.z)
		mat_cielo.set_shader_parameter("dia", dia)
		mat_cielo.set_shader_parameter("nubes", n_val)
		mat_cielo.set_shader_parameter("lluvia", ll_val)
		mat_cielo.set_shader_parameter("tiempo", _tiempo_nubes)
