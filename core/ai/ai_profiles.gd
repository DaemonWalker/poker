class_name AIProfiles extends RefCounted
## AI 显示身份与行为参数表（GDD 4.1 / 4.2 / 4.3，TECH_DESIGN 4.6）。
## 开局时两者解耦抽取：显示身份（IDENTITIES，名字+头像，不重复）决定外观；
## 打法参数从 PARAM_POOL（24 组，可重复）独立随机抽取，ai_profile 存参数组键。
## 每组参数分三层：
##   静态风格 6 项：tightness 紧度 / aggression 激进度 / calling_tendency 跟注倾向 /
##                  bluff_frequency 诈唬频率 / risk_tolerance 风险承受 / position_awareness 位置意识
##   情绪规则 4 项：tilt_sensitivity 输大锅后 tilt 涨幅 / tilt_recovery tilt 衰减速度 /
##                  tilt_looseness_dir tilt 时松度偏移方向(-1 收紧 ~ +1 变松) /
##                  tilt_bluff_dir     tilt 时诈唬偏移方向(-1 ~ +1)
##   对手建模 1 项：adaptability 对手调制幅度（0~1；0 = 完全不学习，等价一期行为）
## 运行时由 AIDecider 计算 有效参数 = 静态参数 + tilt_level × tilt_*_dir + adaptability × 对手偏移。

const DEFAULT_PROFILE := "鲨鱼"

## 8 个固定 AI 显示身份（名字 + 头像 id），仅决定外观，不决定打法（GDD 4.2）。
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

## 8 个具名身份的参考参数表（GDD 4.2 保留为风格基准）。
## 运行时不再按身份取用，开局改用下方 PARAM_POOL 随机抽取；
## 此表保留用于：缺省回落、测试注入（如"老枪"的高 adaptability 对照）、旧存档兼容。
const PROFILES := {
	"石头": {  # 紧弱型：只打强牌，输大锅后更加收紧
		"tightness": 0.85, "aggression": 0.45, "calling_tendency": 0.30,
		"bluff_frequency": 0.05, "risk_tolerance": 0.30, "position_awareness": 0.60,
		"tilt_sensitivity": 0.30, "tilt_recovery": 0.60,
		"tilt_looseness_dir": -0.8, "tilt_bluff_dir": -0.5,
		"adaptability": 0.40,
	},
	"疯子": {  # 疯狂赌徒：什么都玩、爱诈唬，输大锅后报复性变松变诈
		"tightness": 0.20, "aggression": 0.90, "calling_tendency": 0.40,
		"bluff_frequency": 0.45, "risk_tolerance": 0.95, "position_awareness": 0.30,
		"tilt_sensitivity": 0.90, "tilt_recovery": 0.40,
		"tilt_looseness_dir": 1.0, "tilt_bluff_dir": 0.8,
		"adaptability": 0.20,
	},
	"老枪": {  # 老牌手：纪律严明，输大锅后进入"只打坚果"模式且恢复很快
		"tightness": 0.80, "aggression": 0.60, "calling_tendency": 0.35,
		"bluff_frequency": 0.10, "risk_tolerance": 0.40, "position_awareness": 0.90,
		"tilt_sensitivity": 0.25, "tilt_recovery": 0.80,
		"tilt_looseness_dir": -1.0, "tilt_bluff_dir": -0.8,
		"adaptability": 0.90,
	},
	"秤砣": {  # 跟注站：被动爱跟注，输大锅后略微变松（追损失）
		"tightness": 0.55, "aggression": 0.20, "calling_tendency": 0.90,
		"bluff_frequency": 0.05, "risk_tolerance": 0.25, "position_awareness": 0.20,
		"tilt_sensitivity": 0.50, "tilt_recovery": 0.50,
		"tilt_looseness_dir": 0.4, "tilt_bluff_dir": 0.0,
		"adaptability": 0.30,
	},
	"狐狸": {  # 狡猾型：善用位置和诈唬，上头了会加大偷池力度
		"tightness": 0.45, "aggression": 0.70, "calling_tendency": 0.30,
		"bluff_frequency": 0.35, "risk_tolerance": 0.60, "position_awareness": 0.80,
		"tilt_sensitivity": 0.60, "tilt_recovery": 0.70,
		"tilt_looseness_dir": 0.6, "tilt_bluff_dir": 0.6,
		"adaptability": 0.80,
	},
	"鲨鱼": {  # 均衡职业：紧凶、位置感强，输大锅后小幅收紧但更敢反偷
		"tightness": 0.70, "aggression": 0.80, "calling_tendency": 0.30,
		"bluff_frequency": 0.15, "risk_tolerance": 0.55, "position_awareness": 0.90,
		"tilt_sensitivity": 0.40, "tilt_recovery": 0.70,
		"tilt_looseness_dir": -0.4, "tilt_bluff_dir": 0.4,
		"adaptability": 0.85,
	},
	"木头": {  # 岩石型：极紧极被动，几乎不受情绪影响
		"tightness": 0.90, "aggression": 0.30, "calling_tendency": 0.40,
		"bluff_frequency": 0.02, "risk_tolerance": 0.20, "position_awareness": 0.10,
		"tilt_sensitivity": 0.20, "tilt_recovery": 0.50,
		"tilt_looseness_dir": -0.3, "tilt_bluff_dir": -0.3,
		"adaptability": 0.10,
	},
	"浪人": {  # 松凶流浪型：波动大，输大锅后明显变松且很久缓不过来
		"tightness": 0.35, "aggression": 0.65, "calling_tendency": 0.45,
		"bluff_frequency": 0.30, "risk_tolerance": 0.70, "position_awareness": 0.50,
		"tilt_sensitivity": 0.80, "tilt_recovery": 0.30,
		"tilt_looseness_dir": 0.9, "tilt_bluff_dir": 0.5,
		"adaptability": 0.50,
	},
}


## 行为参数池（GDD 4.3）：开局每个 AI 从此表独立随机抽一组（可重复），与显示身份解耦。
## 键 "P01"~"P24" 仅供逻辑层与存档引用，玩家不可见；字段含义与 PROFILES 相同。
const PARAM_POOL := {
	"P01": {  # 紧凶标准
		"tightness": 0.72, "aggression": 0.75, "calling_tendency": 0.30,
		"bluff_frequency": 0.12, "risk_tolerance": 0.50, "position_awareness": 0.85,
		"tilt_sensitivity": 0.35, "tilt_recovery": 0.70,
		"tilt_looseness_dir": -0.5, "tilt_bluff_dir": 0.3,
		"adaptability": 0.80,
	},
	"P02": {  # 紧弱保守
		"tightness": 0.80, "aggression": 0.35, "calling_tendency": 0.35,
		"bluff_frequency": 0.05, "risk_tolerance": 0.25, "position_awareness": 0.55,
		"tilt_sensitivity": 0.30, "tilt_recovery": 0.60,
		"tilt_looseness_dir": -0.8, "tilt_bluff_dir": -0.5,
		"adaptability": 0.45,
	},
	"P03": {  # 松凶压迫
		"tightness": 0.30, "aggression": 0.80, "calling_tendency": 0.35,
		"bluff_frequency": 0.28, "risk_tolerance": 0.75, "position_awareness": 0.60,
		"tilt_sensitivity": 0.65, "tilt_recovery": 0.50,
		"tilt_looseness_dir": 0.8, "tilt_bluff_dir": 0.6,
		"adaptability": 0.60,
	},
	"P04": {  # 松被动跟注站
		"tightness": 0.50, "aggression": 0.20, "calling_tendency": 0.85,
		"bluff_frequency": 0.04, "risk_tolerance": 0.30, "position_awareness": 0.15,
		"tilt_sensitivity": 0.50, "tilt_recovery": 0.45,
		"tilt_looseness_dir": 0.4, "tilt_bluff_dir": 0.0,
		"adaptability": 0.30,
	},
	"P05": {  # 疯狂赌徒
		"tightness": 0.15, "aggression": 0.92, "calling_tendency": 0.45,
		"bluff_frequency": 0.50, "risk_tolerance": 0.95, "position_awareness": 0.25,
		"tilt_sensitivity": 0.90, "tilt_recovery": 0.35,
		"tilt_looseness_dir": 1.0, "tilt_bluff_dir": 0.8,
		"adaptability": 0.15,
	},
	"P06": {  # 坚果纪律
		"tightness": 0.85, "aggression": 0.55, "calling_tendency": 0.25,
		"bluff_frequency": 0.06, "risk_tolerance": 0.35, "position_awareness": 0.90,
		"tilt_sensitivity": 0.20, "tilt_recovery": 0.85,
		"tilt_looseness_dir": -1.0, "tilt_bluff_dir": -0.8,
		"adaptability": 0.90,
	},
	"P07": {  # 岩石
		"tightness": 0.90, "aggression": 0.25, "calling_tendency": 0.40,
		"bluff_frequency": 0.02, "risk_tolerance": 0.18, "position_awareness": 0.10,
		"tilt_sensitivity": 0.15, "tilt_recovery": 0.50,
		"tilt_looseness_dir": -0.3, "tilt_bluff_dir": -0.3,
		"adaptability": 0.10,
	},
	"P08": {  # 偷池型
		"tightness": 0.42, "aggression": 0.68, "calling_tendency": 0.28,
		"bluff_frequency": 0.38, "risk_tolerance": 0.58, "position_awareness": 0.85,
		"tilt_sensitivity": 0.60, "tilt_recovery": 0.70,
		"tilt_looseness_dir": 0.6, "tilt_bluff_dir": 0.7,
		"adaptability": 0.82,
	},
	"P09": {  # 均衡职业
		"tightness": 0.68, "aggression": 0.78, "calling_tendency": 0.30,
		"bluff_frequency": 0.15, "risk_tolerance": 0.55, "position_awareness": 0.88,
		"tilt_sensitivity": 0.40, "tilt_recovery": 0.72,
		"tilt_looseness_dir": -0.4, "tilt_bluff_dir": 0.4,
		"adaptability": 0.85,
	},
	"P10": {  # 波动浪人
		"tightness": 0.35, "aggression": 0.60, "calling_tendency": 0.48,
		"bluff_frequency": 0.30, "risk_tolerance": 0.70, "position_awareness": 0.45,
		"tilt_sensitivity": 0.82, "tilt_recovery": 0.28,
		"tilt_looseness_dir": 0.9, "tilt_bluff_dir": 0.5,
		"adaptability": 0.50,
	},
	"P11": {  # 紧凶情绪化
		"tightness": 0.70, "aggression": 0.70, "calling_tendency": 0.30,
		"bluff_frequency": 0.14, "risk_tolerance": 0.50, "position_awareness": 0.75,
		"tilt_sensitivity": 0.75, "tilt_recovery": 0.40,
		"tilt_looseness_dir": 0.8, "tilt_bluff_dir": 0.7,
		"adaptability": 0.55,
	},
	"P12": {  # 松凶冷静
		"tightness": 0.32, "aggression": 0.75, "calling_tendency": 0.32,
		"bluff_frequency": 0.25, "risk_tolerance": 0.68, "position_awareness": 0.65,
		"tilt_sensitivity": 0.25, "tilt_recovery": 0.75,
		"tilt_looseness_dir": -0.2, "tilt_bluff_dir": -0.1,
		"adaptability": 0.70,
	},
	"P13": {  # 粘池跟注站
		"tightness": 0.58, "aggression": 0.25, "calling_tendency": 0.92,
		"bluff_frequency": 0.06, "risk_tolerance": 0.28, "position_awareness": 0.30,
		"tilt_sensitivity": 0.45, "tilt_recovery": 0.55,
		"tilt_looseness_dir": 0.3, "tilt_bluff_dir": 0.1,
		"adaptability": 0.35,
	},
	"P14": {  # 陷阱型（被动慢打）
		"tightness": 0.60, "aggression": 0.35, "calling_tendency": 0.55,
		"bluff_frequency": 0.20, "risk_tolerance": 0.45, "position_awareness": 0.70,
		"tilt_sensitivity": 0.40, "tilt_recovery": 0.65,
		"tilt_looseness_dir": 0.3, "tilt_bluff_dir": 0.5,
		"adaptability": 0.75,
	},
	"P15": {  # 小注额松稳
		"tightness": 0.40, "aggression": 0.55, "calling_tendency": 0.40,
		"bluff_frequency": 0.20, "risk_tolerance": 0.55, "position_awareness": 0.75,
		"tilt_sensitivity": 0.35, "tilt_recovery": 0.65,
		"tilt_looseness_dir": 0.2, "tilt_bluff_dir": 0.2,
		"adaptability": 0.65,
	},
	"P16": {  # 超紧全下型
		"tightness": 0.82, "aggression": 0.85, "calling_tendency": 0.20,
		"bluff_frequency": 0.08, "risk_tolerance": 0.80, "position_awareness": 0.60,
		"tilt_sensitivity": 0.55, "tilt_recovery": 0.50,
		"tilt_looseness_dir": -0.6, "tilt_bluff_dir": 0.2,
		"adaptability": 0.40,
	},
	"P17": {  # 诈唬狂人
		"tightness": 0.45, "aggression": 0.65, "calling_tendency": 0.30,
		"bluff_frequency": 0.48, "risk_tolerance": 0.65, "position_awareness": 0.55,
		"tilt_sensitivity": 0.70, "tilt_recovery": 0.45,
		"tilt_looseness_dir": 0.7, "tilt_bluff_dir": 0.9,
		"adaptability": 0.45,
	},
	"P18": {  # 防守型
		"tightness": 0.65, "aggression": 0.40, "calling_tendency": 0.60,
		"bluff_frequency": 0.08, "risk_tolerance": 0.35, "position_awareness": 0.50,
		"tilt_sensitivity": 0.35, "tilt_recovery": 0.60,
		"tilt_looseness_dir": -0.5, "tilt_bluff_dir": -0.3,
		"adaptability": 0.50,
	},
	"P19": {  # 位置猎手
		"tightness": 0.50, "aggression": 0.65, "calling_tendency": 0.30,
		"bluff_frequency": 0.30, "risk_tolerance": 0.55, "position_awareness": 0.95,
		"tilt_sensitivity": 0.45, "tilt_recovery": 0.65,
		"tilt_looseness_dir": 0.4, "tilt_bluff_dir": 0.5,
		"adaptability": 0.78,
	},
	"P20": {  # 高适应均衡（学习机器）
		"tightness": 0.60, "aggression": 0.60, "calling_tendency": 0.35,
		"bluff_frequency": 0.18, "risk_tolerance": 0.50, "position_awareness": 0.70,
		"tilt_sensitivity": 0.30, "tilt_recovery": 0.70,
		"tilt_looseness_dir": -0.3, "tilt_bluff_dir": 0.2,
		"adaptability": 0.95,
	},
	"P21": {  # 顽固派（完全不学习）
		"tightness": 0.55, "aggression": 0.55, "calling_tendency": 0.40,
		"bluff_frequency": 0.15, "risk_tolerance": 0.50, "position_awareness": 0.50,
		"tilt_sensitivity": 0.30, "tilt_recovery": 0.60,
		"tilt_looseness_dir": 0.0, "tilt_bluff_dir": 0.0,
		"adaptability": 0.0,
	},
	"P22": {  # 玻璃心紧弱
		"tightness": 0.75, "aggression": 0.40, "calling_tendency": 0.35,
		"bluff_frequency": 0.07, "risk_tolerance": 0.30, "position_awareness": 0.55,
		"tilt_sensitivity": 0.85, "tilt_recovery": 0.30,
		"tilt_looseness_dir": -0.9, "tilt_bluff_dir": -0.7,
		"adaptability": 0.35,
	},
	"P23": {  # 复仇松凶
		"tightness": 0.45, "aggression": 0.70, "calling_tendency": 0.40,
		"bluff_frequency": 0.25, "risk_tolerance": 0.60, "position_awareness": 0.50,
		"tilt_sensitivity": 0.90, "tilt_recovery": 0.25,
		"tilt_looseness_dir": 1.0, "tilt_bluff_dir": 0.8,
		"adaptability": 0.40,
	},
	"P24": {  # 老牌稳重
		"tightness": 0.72, "aggression": 0.58, "calling_tendency": 0.32,
		"bluff_frequency": 0.10, "risk_tolerance": 0.42, "position_awareness": 0.85,
		"tilt_sensitivity": 0.28, "tilt_recovery": 0.80,
		"tilt_looseness_dir": -0.9, "tilt_bluff_dir": -0.6,
		"adaptability": 0.88,
	},
}


static func get_profile(profile_id: String) -> Dictionary:
	if PROFILES.has(profile_id):
		return PROFILES[profile_id]
	return PARAM_POOL.get(profile_id, PROFILES[DEFAULT_PROFILE])
