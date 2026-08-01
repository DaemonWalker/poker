class_name AIProfiles extends RefCounted
## AI 风格参数预设与固定身份名单（GDD 4.1 / 4.2）。
## 风格参数：looseness 松度（入局阈值偏移）、aggression 激进度（加注倾向）、bluff_frequency 诈唬频率。

const PROFILE_TAG := "tag"
const PROFILE_LAG := "lag"
const PROFILE_ROCK := "rock"
const PROFILE_STATION := "station"

const PROFILES := {
	PROFILE_TAG: {"looseness": 0.25, "aggression": 0.80, "bluff_frequency": 0.05},
	PROFILE_LAG: {"looseness": 0.60, "aggression": 0.85, "bluff_frequency": 0.20},
	PROFILE_ROCK: {"looseness": 0.12, "aggression": 0.40, "bluff_frequency": 0.02},
	PROFILE_STATION: {"looseness": 0.55, "aggression": 0.20, "bluff_frequency": 0.05},
}

## 8 个固定 AI 身份（名字 + 头像 id 占位），名单维护于此（GDD 4.2）。
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

## 身份与风格的习惯对应（分配时优先按此配对，身份多于风格时随机补齐）。
const IDENTITY_PREFERRED_PROFILE := {
	"石头": PROFILE_TAG,
	"疯子": PROFILE_LAG,
	"老枪": PROFILE_ROCK,
	"秤砣": PROFILE_STATION,
	"狐狸": PROFILE_LAG,
	"鲨鱼": PROFILE_TAG,
	"木头": PROFILE_ROCK,
	"浪人": PROFILE_LAG,
}


static func get_profile(profile_id: String) -> Dictionary:
	return PROFILES.get(profile_id, PROFILES[PROFILE_TAG])
