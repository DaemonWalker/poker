class_name AIProfiles extends RefCounted
## AI 身份与行为参数表（GDD 4.1 / 4.2，TECH_DESIGN 4.6）。
## 每个身份一张独立参数表（键 = 身份名），分两层：
##   静态风格 6 项：tightness 紧度 / aggression 激进度 / calling_tendency 跟注倾向 /
##                  bluff_frequency 诈唬频率 / risk_tolerance 风险承受 / position_awareness 位置意识
##   情绪规则 4 项：tilt_sensitivity 输大锅后 tilt 涨幅 / tilt_recovery tilt 衰减速度 /
##                  tilt_looseness_dir tilt 时松度偏移方向(-1 收紧 ~ +1 变松) /
##                  tilt_bluff_dir     tilt 时诈唬偏移方向(-1 ~ +1)
## 运行时由 AIDecider 计算 有效参数 = 静态参数 + tilt_level × tilt_*_dir。

const DEFAULT_PROFILE := "鲨鱼"

## 8 个固定 AI 身份（名字 + 头像 id），名单维护于此（GDD 4.2）。
const IDENTITIES := [
	{"name": "石头", "avatar_id": "avatar_rock"},
	{"name": "疯子", "avatar_id": "avatar_maniac"},
	{"name": "老枪", "avatar_id": "avatar_veteran"},
	{"name": "秤砣", "avatar_id": "avatar_anchor"},
	{"name": "狐狸", "avatar_id": "avatar_fox"},
	{"name": "鲨鱼", "avatar_id": "avatar_shark"},
	{"name": "木头", "avatar_id": "avatar_block"},
	{"name": "浪人", "avatar_id": "avatar_drifter"},
]

## 身份 → 行为参数表（键 = 身份名，PlayerState.ai_profile 直接存身份名）。
const PROFILES := {
	"石头": {  # 紧弱型：只打强牌，输大锅后更加收紧
		"tightness": 0.85, "aggression": 0.45, "calling_tendency": 0.30,
		"bluff_frequency": 0.05, "risk_tolerance": 0.30, "position_awareness": 0.60,
		"tilt_sensitivity": 0.30, "tilt_recovery": 0.60,
		"tilt_looseness_dir": -0.8, "tilt_bluff_dir": -0.5,
	},
	"疯子": {  # 疯狂赌徒：什么都玩、爱诈唬，输大锅后报复性变松变诈
		"tightness": 0.20, "aggression": 0.90, "calling_tendency": 0.40,
		"bluff_frequency": 0.45, "risk_tolerance": 0.95, "position_awareness": 0.30,
		"tilt_sensitivity": 0.90, "tilt_recovery": 0.40,
		"tilt_looseness_dir": 1.0, "tilt_bluff_dir": 0.8,
	},
	"老枪": {  # 老牌手：纪律严明，输大锅后进入"只打坚果"模式且恢复很快
		"tightness": 0.80, "aggression": 0.60, "calling_tendency": 0.35,
		"bluff_frequency": 0.10, "risk_tolerance": 0.40, "position_awareness": 0.90,
		"tilt_sensitivity": 0.25, "tilt_recovery": 0.80,
		"tilt_looseness_dir": -1.0, "tilt_bluff_dir": -0.8,
	},
	"秤砣": {  # 跟注站：被动爱跟注，输大锅后略微变松（追损失）
		"tightness": 0.55, "aggression": 0.20, "calling_tendency": 0.90,
		"bluff_frequency": 0.05, "risk_tolerance": 0.25, "position_awareness": 0.20,
		"tilt_sensitivity": 0.50, "tilt_recovery": 0.50,
		"tilt_looseness_dir": 0.4, "tilt_bluff_dir": 0.0,
	},
	"狐狸": {  # 狡猾型：善用位置和诈唬，上头了会加大偷池力度
		"tightness": 0.45, "aggression": 0.70, "calling_tendency": 0.30,
		"bluff_frequency": 0.35, "risk_tolerance": 0.60, "position_awareness": 0.80,
		"tilt_sensitivity": 0.60, "tilt_recovery": 0.70,
		"tilt_looseness_dir": 0.6, "tilt_bluff_dir": 0.6,
	},
	"鲨鱼": {  # 均衡职业：紧凶、位置感强，输大锅后小幅收紧但更敢反偷
		"tightness": 0.70, "aggression": 0.80, "calling_tendency": 0.30,
		"bluff_frequency": 0.15, "risk_tolerance": 0.55, "position_awareness": 0.90,
		"tilt_sensitivity": 0.40, "tilt_recovery": 0.70,
		"tilt_looseness_dir": -0.4, "tilt_bluff_dir": 0.4,
	},
	"木头": {  # 岩石型：极紧极被动，几乎不受情绪影响
		"tightness": 0.90, "aggression": 0.30, "calling_tendency": 0.40,
		"bluff_frequency": 0.02, "risk_tolerance": 0.20, "position_awareness": 0.10,
		"tilt_sensitivity": 0.20, "tilt_recovery": 0.50,
		"tilt_looseness_dir": -0.3, "tilt_bluff_dir": -0.3,
	},
	"浪人": {  # 松凶流浪型：波动大，输大锅后明显变松且很久缓不过来
		"tightness": 0.35, "aggression": 0.65, "calling_tendency": 0.45,
		"bluff_frequency": 0.30, "risk_tolerance": 0.70, "position_awareness": 0.50,
		"tilt_sensitivity": 0.80, "tilt_recovery": 0.30,
		"tilt_looseness_dir": 0.9, "tilt_bluff_dir": 0.5,
	},
}


static func get_profile(profile_id: String) -> Dictionary:
	return PROFILES.get(profile_id, PROFILES[DEFAULT_PROFILE])
