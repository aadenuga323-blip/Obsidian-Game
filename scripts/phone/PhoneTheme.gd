class_name PhoneTheme
## Shared look for the in-game phone: Rajdhani font, dark glass panels, Obsidian accents.
## All phone screens are built in code with these helpers so they stay consistent.

const FONT_PATH := "res://Fonts/Rajdhani-SemiBold.ttf"

# Clean "metropolis" look: graphite handset, off-white screen, white cards,
# charcoal type, one copper accent. Muted secondary colours for tiles and tags.
const ACCENT := Color(0.72, 0.42, 0.18)        # copper (primary actions)
const ACCENT2 := Color(0.27, 0.36, 0.52)       # slate blue (secondary / clan)
const GOLD := Color(0.62, 0.47, 0.16)          # bronze (prices, wallet)
const GREEN := Color(0.22, 0.52, 0.36)         # forest (success, owned)
const RED := Color(0.75, 0.25, 0.22)           # brick (alerts, decline)
const AMBER := Color(0.80, 0.50, 0.14)         # warm amber (vehicles)
const TEXT := Color(0.13, 0.14, 0.17)          # charcoal
const TEXT_DIM := Color(0.46, 0.48, 0.54)      # grey
const SCREEN_BG := Color(0.955, 0.95, 0.94, 1.0)
const CARD_BG := Color(1.0, 1.0, 1.0, 1.0)
const FRAME_BG := Color(0.13, 0.13, 0.14, 1.0)
const LINE := Color(0.0, 0.0, 0.0, 0.08)

static var _font: Font


static func font() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT_PATH):
			_font = load(FONT_PATH)
		else:
			_font = ThemeDB.fallback_font
	return _font


static func fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


static func style(bg: Color, radius := 12, border: Color = LINE, border_w := 1, margin := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_content_margin_all(margin)
	return sb


static func panel(bg: Color = CARD_BG, radius := 12, border: Color = LINE, margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(bg, radius, border, 1, margin))
	return p


static func label(text: String, size := 15, color: Color = TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func wrapped(text: String, size := 13, color: Color = TEXT_DIM) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Primary buttons are solid with white type; TEXT_DIM gives an outlined secondary button.
static func button(text: String, accent: Color = ACCENT, size := 14, min_height := 40) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_height)
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	var secondary := accent == TEXT_DIM
	if secondary:
		b.add_theme_stylebox_override("normal", style(Color(0, 0, 0, 0.03), 10, Color(0, 0, 0, 0.14), 1, 8))
		b.add_theme_stylebox_override("hover", style(Color(0, 0, 0, 0.07), 10, Color(0, 0, 0, 0.22), 1, 8))
		b.add_theme_stylebox_override("pressed", style(Color(0, 0, 0, 0.12), 10, Color(0, 0, 0, 0.3), 1, 8))
		b.add_theme_color_override("font_color", TEXT)
		b.add_theme_color_override("font_hover_color", TEXT)
		b.add_theme_color_override("font_pressed_color", TEXT)
	else:
		b.add_theme_stylebox_override("normal", style(accent, 10, accent, 0, 8))
		b.add_theme_stylebox_override("hover", style(accent.lightened(0.12), 10, accent, 0, 8))
		b.add_theme_stylebox_override("pressed", style(accent.darkened(0.15), 10, accent, 0, 8))
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("disabled", style(Color(0, 0, 0, 0.05), 10, Color(0, 0, 0, 0.08), 1, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.62, 0.66))
	return b


static func tag(text: String, color: Color, size := 11) -> PanelContainer:
	var p := panel(Color(color.r, color.g, color.b, 0.12), 6, Color(color.r, color.g, color.b, 0.45), 5)
	p.add_child(label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


static func progress(value: float, color: Color = ACCENT, height := 10) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.08)
	bg.set_corner_radius_all(height / 2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(height / 2)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fill)
	return p


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func rank_color(rank: String) -> Color:
	match rank:
		"D": return Color(0.5, 0.52, 0.58)
		"C": return ACCENT2
		"B": return GREEN
		"A": return GOLD
		"S", "Elite": return Color(0.5, 0.24, 0.55)
	return TEXT


## App tile colours: muted, distinct, white type.
static func tile_color(app: String) -> Color:
	match app:
		"jobs": return Color(0.27, 0.36, 0.52)
		"property": return Color(0.62, 0.47, 0.16)
		"vehicle": return Color(0.80, 0.50, 0.14)
		"market": return Color(0.22, 0.52, 0.36)
		"clan": return Color(0.5, 0.24, 0.55)
		"gps": return Color(0.2, 0.5, 0.56)
		"stats": return Color(0.3, 0.3, 0.34)
		"contacts": return Color(0.72, 0.42, 0.18)
	return TEXT_DIM
