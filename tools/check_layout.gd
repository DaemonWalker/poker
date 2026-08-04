extends SceneTree
## 临时布局校验：实测 SeatUI 尺寸，按 table_scene 椭圆公式检测 2~9 人桌座位重叠。
## godot --headless --path . --script tools/check_layout.gd

const SEAT_CENTER := Vector2(640, 324)
const SEAT_RADIUS := Vector2(500, 205)
const SEAT_OFFSET := Vector2(-85, -65)

## 固定 UI 区域（scenes/table.tscn），座位不得压入。
const UI_ZONES := {
	"TopBar": Rect2(340, 6, 600, 26),
	"MenuButton": Rect2(1150, 4, 120, 30),
	"StreetLabel": Rect2(590, 206, 100, 22),
	"PotLabel": Rect2(490, 230, 300, 30),
	"CommunityCards": Rect2(472, 280, 336, 80),
	"MessageLabel": Rect2(390, 360, 500, 34),
	"ActionPanel": Rect2(240, 596, 800, 114),
}

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# 实测座位面板尺寸（_init 里 add_child 不触发 _ready，须在 deferred 里做）
	var seat := SeatUI.new()
	root.add_child(seat)
	seat.show_backs()  # 底牌隐藏时容器收缩，按对局中的最大高度测量
	await process_frame
	await process_frame
	var seat_size: Vector2 = seat.size
	print("SeatUI 实测尺寸: %v" % seat_size)
	seat.queue_free()

	var fail := false
	for count in range(2, 10):
		var rects: Array[Rect2] = []
		for i in count:
			var angle := deg_to_rad(90.0 + 360.0 * i / count)
			var center := SEAT_CENTER + Vector2(cos(angle), sin(angle)) * SEAT_RADIUS
			rects.append(Rect2(center + SEAT_OFFSET, seat_size))
		for i in count:
			if not Rect2(0, 0, 1280, 720).encloses(rects[i]):
				print("  [失败] %d 人桌：座位 %d 超出屏幕 %s" % [count, i, rects[i]])
				fail = true
			for j in range(i + 1, count):
				if rects[i].intersects(rects[j]):
					print("  [失败] %d 人桌：座位 %d 与 %d 重叠" % [count, i, j])
					fail = true
			for zone: String in UI_ZONES:
				if rects[i].intersects(UI_ZONES[zone]):
					print("  [失败] %d 人桌：座位 %d 压住 %s" % [count, i, zone])
					fail = true
	if fail:
		printerr("结果：存在重叠")
		quit(1)
	else:
		print("结果：2~9 人桌全部无重叠")
		quit(0)
