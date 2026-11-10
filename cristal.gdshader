shader_type canvas_item;

// ======================================================================
//  cristal.gdshader - vidrio esmerilado oscuro con borde de NIEBLA
//  1) Desenfoca lo que hay detras (la escena 3D).
//  2) Lo oscurece con un tinte negro translucido.
//  3) La opacidad cae suavemente hacia el borde (niebla).
//  Esquinas: 'radio' para todas, o 'radios' (arr-izq, arr-der, abj-der,
//  abj-izq) para redondear solo algunas (-1 = usar 'radio').
//  'ligero' = true: una sola muestra en vez de 12 (paneles grandes).
// ======================================================================

uniform sampler2D pantalla : hint_screen_texture, filter_linear_mipmap;
uniform vec2 tam = vec2(400.0, 300.0);
uniform float radio = 24.0;
uniform vec4 radios = vec4(-1.0);
uniform bool ligero = false;
uniform float niebla = 30.0;
uniform float borde_alfa = 0.40;
uniform float linea = 1.5;
uniform vec4 linea_color : source_color = vec4(1.0, 1.0, 1.0, 0.32);
uniform float desenfoque = 6.0;
uniform float oscuridad = 0.62;
uniform float opacidad = 1.0;
uniform vec4 tinte : source_color = vec4(0.0, 0.0, 0.0, 1.0);

const int MUESTRAS = 12;

// distancia con signo a una caja con radio distinto en cada esquina
float caja_redonda(vec2 p, vec2 mitad, vec4 rs) {
	float r = (p.x < 0.0) ? ((p.y < 0.0) ? rs.x : rs.w) : ((p.y < 0.0) ? rs.y : rs.z);
	vec2 q = abs(p) - mitad + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * tam;
	float tope = min(tam.x, tam.y) * 0.5;
	vec4 rs = (radios.x >= 0.0) ? radios : vec4(radio);
	rs = min(rs, vec4(tope));
	float d = caja_redonda(px - tam * 0.5, tam * 0.5, rs);

	float forma = 1.0 - smoothstep(-0.5, 0.5, d);

	float f = clamp(-d / max(niebla, 1.0), 0.0, 1.0);
	f = f * f * (3.0 - 2.0 * f);
	float relleno = mix(borde_alfa, 1.0, f);

	float mitad_l = linea * 0.5;
	float rim = 1.0 - smoothstep(mitad_l - 0.5, mitad_l + 0.5, abs(d + mitad_l));

	vec3 borroso;
	if (ligero) {
		borroso = textureLod(pantalla, SCREEN_UV, 2.5).rgb;
	} else {
		vec2 paso = SCREEN_PIXEL_SIZE * desenfoque;
		vec3 acc = vec3(0.0);
		for (int i = 0; i < MUESTRAS; i++) {
			float a = float(i) * 2.399963;
			float rr = sqrt((float(i) + 0.5) / float(MUESTRAS));
			vec2 o = vec2(cos(a), sin(a)) * rr * paso;
			acc += textureLod(pantalla, SCREEN_UV + o, 1.5).rgb;
		}
		borroso = acc / float(MUESTRAS);
	}

	vec3 col = mix(borroso, tinte.rgb, oscuridad);
	col = mix(col, linea_color.rgb, rim * linea_color.a);
	float alfa = max(relleno, rim * linea_color.a);
	COLOR = vec4(col, forma * alfa * opacidad);
}
