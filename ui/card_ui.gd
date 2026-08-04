class_name CardUI extends PanelContainer
## 单张牌显示组件：playing-cards-assets 扑克牌贴图（MIT，assets/cards/，来源见 assets/SOURCES.md）。
## 贴图缺失时降级为占位色块 + 文字；翻面动画（pivot 缩放）与贴图无关。

const SIZE := Vector2(56, 80)
const COLOR_FACE := Color(0.95, 0.95, 0.9)
const COLOR_BACK := Color(0.2, 0.3, 0.5)
const COLOR_EMPTY := Color(1, 1, 1, 0.08)
const COLOR_RED := Color(0.8, 0.15, 0.15)
const COLOR_BLACK := Color(0.15, 0.15, 0.15)

## 贴图目录与命名映射：card_<花色>_<点数>.png（花色 0黑桃 1红桃 2梅花 3方块）。
const TEX_DIR := "res://assets/cards/"
const SUIT_NAMES := ["spades", "hearts", "clubs", "diamonds"]

static var _tex_cache: Dictionary = {}

## 实例尺寸（座位区小牌用更小的尺寸，须在 add_child 触发 _ready 前设置）。
var card_size := SIZE

var _label: Label
var _texture: TextureRect


func _ready() -> void:
	custom_minimum_size = card_size
	pivot_offset = card_size / 2  # 翻面动画绕中心缩放
	_texture = TextureRect.new()
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_texture)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	add_child(_label)
	clear()


## A2/A5 翻面动画：横向压扁 → 换牌面 → 展开（dur 为半程时长）。
func flip_to_card(card: Card, dur: float) -> void:
	var t := create_tween()
	t.tween_property(self, "scale:x", 0.0, dur)
	t.tween_callback(set_card.bind(card))
	t.tween_property(self, "scale:x", 1.0, dur)
	await t.finished


## 显示牌面（贴图优先，缺失时降级为色块 + 文字，红桃/方块用红色字）。
func set_card(card: Card) -> void:
	visible = true
	var tex := _load_tex(_face_path(card))
	if tex != null:
		_show_tex(tex)
		return
	_texture.hide()
	_label.show()
	_set_bg(COLOR_FACE)
	_label.text = card.to_string_short()
	# suit: 0=黑桃 1=红桃 2=梅花 3=方块
	_label.add_theme_color_override("font_color",
			COLOR_RED if card.suit == 1 or card.suit == 3 else COLOR_BLACK)


## 显示牌背（AI 底牌）。
func set_back() -> void:
	visible = true
	var tex := _load_tex(TEX_DIR + "card_back.png")
	if tex != null:
		_show_tex(tex)
		return
	_texture.hide()
	_label.show()
	_set_bg(COLOR_BACK)
	_label.text = "?"
	_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))


## 空槽位（贴图为镂空牌框，缺失时半透明占位）。
func clear() -> void:
	visible = true
	var tex := _load_tex(TEX_DIR + "card_empty.png")
	if tex != null:
		_show_tex(tex)
		return
	_texture.hide()
	_label.show()
	_set_bg(COLOR_EMPTY)
	_label.text = ""


## 彻底隐藏（该座位无牌）。
func hide_card() -> void:
	visible = false


## 牌面贴图路径：点数 2~9 补零，T→10，J/Q/K/A 直用。
static func _face_path(card: Card) -> String:
	var rank_char := Card.RANK_CHARS[card.rank - 2]
	var rank_name := rank_char
	if rank_char == "T":
		rank_name = "10"
	elif rank_char.length() == 1 and "23456789".contains(rank_char):
		rank_name = "0" + rank_char
	return "%scard_%s_%s.png" % [TEX_DIR, SUIT_NAMES[card.suit], rank_name]


## 带缓存的贴图加载；文件不存在返回 null（不报错，走降级显示）。
static func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[path] = tex
	return tex


## 贴图显示：面板背景透明化，隐藏文字。
func _show_tex(tex: Texture2D) -> void:
	_set_bg(Color(0, 0, 0, 0))
	_texture.texture = tex
	_texture.show()
	_label.hide()


func _set_bg(color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
