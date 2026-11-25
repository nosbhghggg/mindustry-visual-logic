class_name LinkRouter
extends RefCounted

## 跳线路由（纯函数）：把「谁引用了谁」算成一组可直接绘制的折线。
## 同链按「宿主 C 形块通道 + 目标 + 方向」合并成母线束统一排轨道；跨链走独立的走廊过桥折线。

# ── 基础几何常量（像素） ──
const LANE_GAP: float = 14.0        # 第 0 号母线到积木左边缘的间距
const LANE_STEP: float = 10.0       # 每外扩一道母线再加的间距
const CUT_RATIO: float = 0.5        # 同链梯形拐角最大斜率（2:1 斜切）
const MIN_BUS: float = 20.0         # 同链母线竖直段保底长度
const ROW_HEIGHT: float = 40.0      # 积木标题行高度
const HEADER_HALF: float = 20.0     # 标题行正中偏移
const NEST_INDENT: float = 24.0     # C 形块内部子块的缩进
const END_DROP: float = 4.0         # 到达端上移量（错开同块进出双箭头）
const CROSS_CHAMFER: float = 12.0   # 跨链过桥折线的最大 45 度倒角

# ── 同链排序权重（单位：跨越的积木行数） ──
const BRANCH_PENALTY: int = 2       # 每多一条支线汇入，权重减 2 行（优先占内道）
const LOOP_BONUS: int = 3           # 回跳的线权重加 3 行（退到外道包住内部）


## 计算画布上全部跳线的折线顶点与颜色。
static func segments(graph: LogicGraph, library: BlockLibrary, layout: LayoutResult) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if graph == null or library == null or layout == null:
		return out

	var local_bundles_by_ch: Dictionary = {} # 通道 → 该通道的母线束列表
	var local_bundle_map: Dictionary = {}    # 母线束键 → 母线束（合并同束的多个源）

	# 第一阶段：同链收集母线束，跨链当场出折线
	graph.each_link_ref(
			func(node: LogicNode) -> Array[StringName]:
				var def := library.by_id(node.type_id)
				return def.reference_fields() if def != null else [] as Array[StringName],
			func(ref: Dictionary) -> void:
				var target: int = ref["target"]
				if target <= 0:
					return
				var source_id: int = (ref["node"] as LogicNode).id

				# c_s / c_t：源与目标所属顶层链的整数序号
				var c_s: int = layout.chain_ids.get(source_id, -1)
				var c_t: int = layout.chain_ids.get(target, -1)
				if c_s < 0 or c_t < 0:
					return

				if c_s == c_t:
					var s_ord: int = layout.orders[source_id]
					var t_ord: int = layout.orders[target]
					var flipped: bool = s_ord > t_ord # 起点行号 > 终点行号 = 从下往上回跳

					var top_y: float = layout.rect_of(target if flipped else source_id).position.y + HEADER_HALF
					var bottom_y: float = layout.rect_of(source_id if flipped else target).position.y + HEADER_HALF

					# 找能完整包住这段区间的最小 C 形块（防跳线穿过它的标题行）
					var scope := _find_scope_by_owner(source_id, top_y, bottom_y, layout)
					var host_id: int = int(scope["host_id"])        # 包住该跳线的 C 形块 ID（顶层为 0）
					var anchor_x: float = float(scope["anchor_x"])  # 该通道母线贴靠的左边缘 X

					# 通道键 = (链序号, 宿主 C 形块)；母线束键 = 通道 + 目标 + 方向。
					# 用 Vector 值类型做键：手工拼位段在 id 变大后会互相重叠。
					var ch_key := Vector2i(c_s, host_id)
					var bundle_key := Vector4i(c_s, host_id, target, 1 if flipped else 0)

					var bundle: Dictionary = local_bundle_map.get(bundle_key, {})
					if bundle.is_empty():
						bundle = {
							"target": target,
							"flipped": flipped,
							"top": mini(s_ord, t_ord),    # 行号区间覆盖源与目标两端
							"bottom": maxi(s_ord, t_ord),
							"anchor_x": anchor_x,
							"lane": 0,
							"starts": [] as Array[int],
						}
						local_bundle_map[bundle_key] = bundle
						if not local_bundles_by_ch.has(ch_key):
							local_bundles_by_ch[ch_key] = [] as Array[Dictionary]
						(local_bundles_by_ch[ch_key] as Array[Dictionary]).append(bundle)
					# 每次都收紧上下界：all_ids 的遍历顺序与布局顺序不保证一致
					(bundle["starts"] as Array[int]).append(source_id)
					bundle["top"] = mini(int(bundle["top"]), s_ord)
					bundle["bottom"] = maxi(int(bundle["bottom"]), s_ord)
				else:
					out.append({
						"points": _route_cross(layout, source_id, target),
						"color": color_for(target),
						"is_cross": true,
					})
	)

	# 第二阶段：按通道排轨道，再逐源生成同链折线
	for ch_key in local_bundles_by_ch:
		var ch_bundles: Array[Dictionary] = local_bundles_by_ch[ch_key]
		_assign_lanes(ch_bundles)
		for bundle in ch_bundles:
			var target_id: int = int(bundle["target"])
			var end := anchor_left(layout, target_id, true) - Vector2(0.0, END_DROP)
			var color := color_for(target_id)
			var lane_x: float = float(bundle["anchor_x"]) - LANE_GAP - float(bundle["lane"]) * LANE_STEP
			for src_id: int in bundle["starts"]:
				out.append({
					"points": _route_curve(anchor_left(layout, src_id), end, lane_x),
					"color": color,
					"is_cross": false,
				})

	return out


## 顺着 owners 向上找能完整包住 [top_y, bottom_y] 的最小 C 形块（顶层返回 host_id = 0）。
static func _find_scope_by_owner(source_id: int, top_y: float, bottom_y: float, layout: LayoutResult) -> Dictionary:
	var cur := source_id
	var owner: int = layout.owners.get(cur, 0)
	while owner != 0:
		var r := layout.rect_of(owner)
		# [top_y, bottom_y] 必须整个落在该 C 形块的肚子里（标题行以下、底边以上）
		if r.position.y + ROW_HEIGHT <= top_y and r.end.y >= bottom_y:
			return {"host_id": owner, "anchor_x": r.position.x + NEST_INDENT}
		cur = owner
		owner = layout.owners.get(cur, 0)
	# 到顶了：cur 就是最外层积木，用它的左边缘作为整条链的基准线
	return {"host_id": 0, "anchor_x": layout.rect_of(cur).position.x}


## 积木左边缘锚点：[param mid_y] 为真取竖直中点（到达端），否则取标题行中点（出发端）。
static func anchor_left(layout: LayoutResult, id: int, mid_y: bool = false) -> Vector2:
	return _anchor(layout, id, mid_y, false)


## 积木右边缘锚点：C 形块右侧是缺口，只能落在标题行，[param mid_y] 对它无效。
static func anchor_right(layout: LayoutResult, id: int, mid_y: bool = false) -> Vector2:
	return _anchor(layout, id, mid_y and not _has_nest(layout, id), true)


static func _anchor(layout: LayoutResult, id: int, mid_y: bool, right: bool) -> Vector2:
	if layout == null:
		return Vector2.ZERO
	var rect := layout.rect_of(id)
	var y := rect.position.y + (rect.size.y * 0.5 if mid_y else HEADER_HALF)
	return Vector2(rect.position.x + (rect.size.x if right else 0.0), y)


## C 形块的判据：只有 nest 行会写 slot_offsets。
static func _has_nest(layout: LayoutResult, id: int) -> bool:
	if layout == null:
		return false
	var metrics: BlockMetrics = layout.metrics.get(id)
	return metrics != null and not metrics.slot_offsets.is_empty()


## 根据目标积木 ID 生成固定颜色（黄金分割乘法哈希）。
static func color_for(target_id: int) -> Color:
	var h: int = (hash(target_id) * 2654435761) & 0x7FFFFFFF
	return Color.from_hsv(float(h % 360) / 360.0, 0.65, 0.95)


## 排序权重（单位：跨越行数，越小越先占内侧第 0 道）：跨度 - 多分支减分 + 回跳加分。
static func _bundle_weight(b: Dictionary) -> int:
	var branches: int = maxi(0, (b["starts"] as Array).size() - 1)
	return int(b["bottom"]) - int(b["top"]) - branches * BRANCH_PENALTY + (LOOP_BONUS if bool(b["flipped"]) else 0)


## 通道内纯整数装箱算法：基于整数行号区间 [top, bottom] 完成权重排序、包含让道与重叠避让。
## 区间半开处理（[top, bottom)）：原判定 cur_top < o_bottom && cur_bottom > o_top 正是半开相交；
## top == bottom 的零长束（自跳）单独按点处理。轨道号 ≥ 62 时位掩码装不下，退回逐对版本。
static func _assign_lanes(bundles: Array[Dictionary]) -> void:
	bundles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var wa := _bundle_weight(a)
		var wb := _bundle_weight(b)
		if wa != wb:
			return wa < wb
		var top_a: int = int(a["top"])
		var top_b: int = int(b["top"])
		if top_a != top_b:
			return top_a < top_b
		return int(a["target"]) < int(b["target"])
	)
	if not _assign_lanes_indexed(bundles):
		_assign_lanes_pairwise(bundles)


## 线段树版：相交查询用「正覆盖本段的轨道」位掩码树（own = 本段 canonical 存入的区间，
## sub = 子树并集）——与查询区间相交的节点上，own/sub 里的区间必与查询相交，一次遍历 O(log N)。
## 包含查询是另一棵树：按 top 坐标存「每条轨道的最小 bottom」，top ≥ cur_top 且 min_bottom ≤ cur_bottom
## 即被包含（canonical 节点落在查询里 ≠ 整段被包含，区间会从别的 canonical 节点伸出查询外）。
static func _assign_lanes_indexed(bundles: Array[Dictionary]) -> bool:
	var n := 1
	for b in bundles:
		n = maxi(n, int(b["bottom"]))
	var size := 1
	while size < n:
		size <<= 1
	var own := PackedInt64Array()
	own.resize(2 * size)
	var sub := PackedInt64Array()
	sub.resize(2 * size)
	var cmin: Array[Dictionary] = [] # top 坐标树：节点 → {lane: 最小 bottom}
	cmin.resize(2 * size)
	for i in cmin.size():
		cmin[i] = {}
	var points: Array[Dictionary] = [] # 零长束 {pos, lane}：半开区间里是空集，树查不到
	for i in bundles.size():
		var cur: Dictionary = bundles[i]
		var t: int = int(cur["top"])
		var b: int = int(cur["bottom"])
		var overlap := 0
		var contained := 0
		if t < b:
			overlap = _lane_overlap(own, sub, 1, 0, size, t, b)
			contained = _lane_contained(cmin, size, t, b)
		elif t > 0:
			# 零长束与 [o_top, o_bottom) 相交 ⟺ o_top < t < o_bottom（两端都严格）：
			# 取 [t, t+1) 与 [t-1, t) 两次相交查询的掩码交集
			overlap = _lane_overlap(own, sub, 1, 0, size, t, t + 1) \
					& _lane_overlap(own, sub, 1, 0, size, t - 1, t)
		for p in points:
			var pos: int = int(p["pos"])
			var bit := 1 << int(p["lane"])
			if t < b:
				if pos > t and pos < b:
					overlap |= bit
				if pos >= t and pos <= b:
					contained |= bit
			elif pos == t:
				contained |= bit
		var base_lane := 0
		var m := contained
		while m != 0:
			m >>= 1
			base_lane += 1
		var lane := base_lane
		while lane < 62 and ((overlap >> lane) & 1) != 0:
			lane += 1
		if lane >= 62:
			return false
		cur["lane"] = lane
		if t < b:
			_lane_insert(own, sub, size, t, b, 1 << lane)
			_lane_cmin_insert(cmin, size, t, b, lane)
		else:
			points.append({"pos": t, "lane": lane})
	return true


static func _lane_insert(own: PackedInt64Array, sub: PackedInt64Array, size: int,
		l: int, r: int, bit: int) -> void:
	l += size
	r += size
	while l < r:
		if (l & 1) != 0:
			_lane_add(own, sub, size, l, bit)
			l += 1
		if (r & 1) != 0:
			r -= 1
			_lane_add(own, sub, size, r, bit)
		l >>= 1
		r >>= 1


static func _lane_add(own: PackedInt64Array, sub: PackedInt64Array, size: int,
		node: int, bit: int) -> void:
	own[node] |= bit
	sub[node] |= bit
	node >>= 1
	while node > 0:
		sub[node] = own[node] | sub[node * 2] | sub[node * 2 + 1]
		node >>= 1


static func _lane_overlap(own: PackedInt64Array, sub: PackedInt64Array, node: int,
		nl: int, nr: int, l: int, r: int) -> int:
	if nr <= l or nl >= r:
		return 0
	if l <= nl and nr <= r:
		return sub[node]
	var mid := (nl + nr) >> 1
	return own[node] | _lane_overlap(own, sub, node * 2, nl, mid, l, r) \
			| _lane_overlap(own, sub, node * 2 + 1, mid, nr, l, r)


static func _lane_cmin_insert(cmin: Array[Dictionary], size: int, top: int, bottom: int, lane: int) -> void:
	var node := top + size
	while node > 0:
		var mins: Dictionary = cmin[node]
		mins[lane] = mini(int(mins.get(lane, bottom)), bottom)
		node >>= 1


## 被 [t, b] 完整包含的已占轨道集：top ≥ t 的区间里，最小 bottom ≤ b 的那些轨道。
static func _lane_contained(cmin: Array[Dictionary], size: int, t: int, b: int) -> int:
	var mask := 0
	var l := t + size
	var r := size + size
	while l < r:
		if (l & 1) != 0:
			mask |= _cmin_collect(cmin[l], b)
			l += 1
		if (r & 1) != 0:
			r -= 1
			mask |= _cmin_collect(cmin[r], b)
		l >>= 1
		r >>= 1
	return mask


static func _cmin_collect(mins: Dictionary, b: int) -> int:
	var mask := 0
	for lane in mins:
		if int(mins[lane]) <= b:
			mask |= 1 << int(lane)
	return mask


## 逐对扫描版（轨道号超出位掩码时的兜底；也是索引版的比对基准）：语义与索引版逐字一致。
static func _assign_lanes_pairwise(bundles: Array[Dictionary]) -> void:
	for i in bundles.size():
		var cur: Dictionary = bundles[i]
		var cur_top: int = int(cur["top"])
		var cur_bottom: int = int(cur["bottom"])

		var base_lane := 0
		var occupied_lanes: Dictionary = {}

		for j in i:
			var other: Dictionary = bundles[j]
			var o_top: int = int(other["top"])
			var o_bottom: int = int(other["bottom"])

			# 包含让道：若 other 完整处在 cur 区间内部，cur 必须排在 other 外侧（轨道号 + 1）
			if o_top >= cur_top and o_bottom <= cur_bottom:
				base_lane = maxi(base_lane, int(other["lane"]) + 1)

			# 相交避让：若两束行号区间有重叠，拉黑 other 已占用的轨道号
			if cur_top < o_bottom and cur_bottom > o_top:
				occupied_lanes[int(other["lane"])] = true

		var lane := base_lane
		while occupied_lanes.has(lane):
			lane += 1
		cur["lane"] = lane


## 同链 4 点梯形折线（内部按起止高度算动态斜率）。
static func _route_curve(start: Vector2, end: Vector2, lane_x: float) -> PackedVector2Array:
	var span_y := absf(end.y - start.y)
	var span_x := absf(lane_x - end.x) + absf(lane_x - start.x)
	var slope := clampf((span_y - MIN_BUS) / span_x if span_x > 0.0 else 0.0, 0.0, CUT_RATIO)
	var dir_y := signf(end.y - start.y)

	return PackedVector2Array([
		start,
		Vector2(lane_x, start.y + dir_y * (start.x - lane_x) * slope),
		Vector2(lane_x, end.y - dir_y * (end.x - lane_x) * slope),
		end,
	])


## 跨链走廊折线：按两块的水平位置关系选端点与走廊。
static func _route_cross(layout: LayoutResult, source_id: int, target_id: int) -> PackedVector2Array:
	var drop := Vector2(0.0, END_DROP)
	var sl := anchor_left(layout, source_id)
	var sr := anchor_right(layout, source_id)
	var tl := anchor_left(layout, target_id, true) - drop
	var tr := anchor_right(layout, target_id, true) - drop

	var start: Vector2
	var end: Vector2
	var mid_x: float
	if sr.x <= tl.x:
		# 源在左：右出 -> 左进，走廊走两链正中间
		start = sr
		end = tl
		mid_x = (sr.x + tl.x) * 0.5
	elif sl.x >= tr.x:
		# 源在右：左出 -> 右进，走廊走两链正中间
		start = sl
		end = tr
		mid_x = (sl.x + tr.x) * 0.5
	else:
		# 两链水平重叠：从左侧外绕
		start = sl
		end = tl
		mid_x = minf(sl.x, tl.x) - LANE_GAP

	var dy := end.y - start.y
	# 两端几乎齐平时直接连直线
	if absf(dy) <= END_DROP and start.x != end.x:
		return PackedVector2Array([start, end])

	var dir_y := 1.0 if dy >= 0.0 else -1.0
	var chamfer := clampf(
			minf(absf(mid_x - start.x), absf(end.x - mid_x)) * 0.4,
			0.0, minf(absf(dy) * 0.3, CROSS_CHAMFER)
	)
	if chamfer < 2.0:
		return PackedVector2Array([start, Vector2(mid_x, start.y), Vector2(mid_x, end.y), end])

	var out_dir := signf(mid_x - start.x)
	var in_dir := signf(end.x - mid_x)
	return PackedVector2Array([
		start,
		Vector2(mid_x - out_dir * chamfer, start.y),
		Vector2(mid_x, start.y + dir_y * chamfer),
		Vector2(mid_x, end.y - dir_y * chamfer),
		Vector2(mid_x + in_dir * chamfer, end.y),
		end,
	])