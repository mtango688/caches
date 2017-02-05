-- Minetest mod: Caches
-- requires default, Technic, Pipeworks, and Moreores

-- license: WTFPL

-- definitions

local tiers = {
	{	name = "cache",
		description = "Cache",
		capacity = 10000,
		material = "moreores:tin_ingot",
		base = "group:tree",
		texture = "caches_cache.png"
	},
	{	name = "cache_harden",
		description = "Hardened Cache",
		capacity = 40000,
		material = "technic:carbon_steel_ingot",
		base = "caches:cache",
		texture = "caches_hardened.png"
	},
	{	name = "cache_reinfo",
		description = "Reinforced Cache",
		capacity = 160000,
		material = "default:obsidian_glass",
		base = "caches:cache_harden",
		texture = "caches_reinforced.png"
	},
	{	name = "cache_arcane",
		description = "Arcane Cache",
		capacity = 640000,
		material = "moreores:mithril_ingot",
		base = "caches:cache_reinfo",
		texture = "caches_arcane.png"
	},
}

local default_texture = "default_obsidian_glass_detail.png"

-- update cache button toggles

local function update_formspec(pos)
	local meta = minetest.get_meta(pos)
	local name = meta:get_string("name")
	local locked = meta:get_int("locked")
	local output = meta:get_int("output")

	if locked == 0 then
		locks = "lock;Lock"
	else
		locks = "unlock;Unlock"
	end
	if output == 0 then
		outs = "output;Output"
	else
		outs = "stop;Stop"
	end

	meta:set_string("showform", "size[4,3]"..
			default.gui_bg..
			default.gui_bg_img..
			default.gui_slots..
			"button_exit[0,0;2,1;store;Store]"..
			"button_exit[2,0;2,1;take;Take]"..
			"button_exit[0,1;2,1;"..locks.."]"..
			"button_exit[2,1;2,1;"..outs.."]"..
			"button_exit[1,2;2,1;transfer;Transfer]"
		)
end

-- find the entity associated with a cache, if any

local function find_visual(pos)
	local objs = minetest.get_objects_inside_radius(pos, 0.65)
	if objs then
		for _, obj in pairs(objs) do
			if obj and obj:get_luaentity() and
					obj:get_luaentity().name == "caches:visual" then
				return obj
			end
		end
	end
end

-- get inventory image

local function get_inv_image(name)
	local t = default_texture
	local d = minetest.registered_items[name]
	if name ~= "air" and d then
		if d.inventory_image and #d.inventory_image > 0 then
			t = d.inventory_image
		else
			local c = #d.tiles
			local x = {}
			for i, v in ipairs(d.tiles) do
				if type(v) == "table" then
					x[i] = v.name
				else
					x[i] = v
				end
				i = i + 1
			end
			if not x[3] then x[3] = x[1] end
			if not x[4] then x[4] = x[3] end
			t = minetest.inventorycube(x[1], x[3], x[4])
		end
	end
	return t
end

-- update info about this cache

local function update_infotext(pos)
	local meta = minetest.get_meta(pos)
	local capacity = meta:get_int("capacity")
	local count = meta:get_int("count")
	local name = meta:get_string("name")
	local locked = meta:get_int("locked")

	local item = ""
	if name ~= "air" then
		local def = minetest.registered_items[name]
		if def and def.description then item = def.description end
	end

	meta:set_string("infotext", item.." "..tostring(count).." / "..
		tostring(capacity))

	-- update visual

	local obj = find_visual(pos)
	if not obj then
		local node = minetest.get_node(pos)
		local bdir = minetest.facedir_to_dir(node.param2)
		local fdir = vector.new(-bdir.x, 0, -bdir.z)
		local pos2 = vector.add(pos, vector.multiply(fdir, 0.51))
		obj = minetest.add_entity(pos2, "caches:visual")
		if bdir.x < 0 then obj:setyaw(0.5 * math.pi) end
		if bdir.z < 0 then obj:setyaw(math.pi) end
		if bdir.x > 0 then obj:setyaw(1.5 * math.pi) end
	end
	if obj then
		local t = get_inv_image(name)
		if locked > 0 then t = t.."^caches_locked.png" end
		obj:set_properties({textures = {t}})
	end
end

-- put indicated stack of items into cache, returns leftovers

local function add_item(pos, stack)
	local meta = minetest.get_meta(pos)
	local name = meta:get_string("name")
	local capacity = meta:get_int("capacity")
	local cache_count = meta:get_int("count")
	local locked = meta:get_int("locked")
	local left_over = ItemStack(stack)
	local stack_count = stack:get_count()

	-- cancel if itemstack is 0 or a unique thing
	if stack_count == 0 or stack:get_stack_max() == 1 then return stack end

	if (locked == 0 and cache_count == 0) or stack:get_name() == name then
		if cache_count < capacity then
			local real_count = math.min(capacity - cache_count, stack_count)
			meta:set_int("count", cache_count + real_count)
			if stack:get_name() ~= name then
				meta:set_string("name", stack:get_name())
			end
			if stack_count == real_count then
				left_over:clear()
			else
				left_over:set_count(stack_count - real_count)
			end
			update_infotext(pos)
		end
	end
	
	return left_over
end

-- return whether the the stack fully fits within the cache

local function room_for_item(pos, stack)
	local meta = minetest.get_meta(pos)
	local name = meta:get_string("name")
	local capacity = meta:get_int("capacity")
	local cache_count = meta:get_int("count")
	local locked = meta:get_int("locked")

	-- cancel if itemstack is 0 or a unique thing
	if stack:get_count() == 0 or stack:get_stack_max() == 1 then return false end

	if (locked == 0 and cache_count == 0) or stack:get_name() == name then
		if cache_count + stack:get_count() <= capacity then
			return true
		else
			return false
		end
	end
end

-- take items from cache and transfer them to inv
-- do_stack is an optional bool indicating whether to take a max stack
-- returns true if anything was transferred

local function remove_item(pos, inv, listname, do_stack)
	local meta = minetest.get_meta(pos)
	local cache_count = meta:get_int("count")
	local locked = meta:get_int("locked")

	if cache_count > 0 then
		local name = meta:get_string("name")
		local real_count = 1
		if do_stack then
			real_count = ItemStack(name):get_stack_max()
		end
		if real_count > cache_count then real_count = cache_count end

		local stack = ItemStack(name)
		stack:set_count(real_count)
		if inv:room_for_item(listname, stack) then
			inv:add_item(listname, stack)
			meta:set_int("count", cache_count - real_count)
			if cache_count == real_count and locked == 0 then
				meta:set_string("name", "air")
			end
			update_infotext(pos)
			return true
		end
	end

	return false
end

-- check whether the player has access to the cache

local function can_access(pos, player)
	if minetest.is_protected(pos, player) then
		minetest.chat_send_player(player:get_player_name(),
			"You are not permitted to access caches in this area.")
		return false
	end
	return true
end

-- update description in itemstack

local function update_description(item, name, count, capacity)
	local i = "Empty"
	if name ~= "air" then
		local def = minetest.registered_items[name]
		if def and def.description then i = def.description end
	end

	local d = i.." "..tostring(count).." / "..tostring(capacity)
	item:get_meta():set_string("description", d)
end

-- other features

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if string.sub(formname, 1, 12) ~= "caches:cache" then return end
	local pos = minetest.string_to_pos(string.sub(formname, 13))

	local meta = minetest.get_meta(pos)
	local name = meta:get_string("name")
	local capacity = meta:get_int("capacity")
	local count = meta:get_int("count")
	local locked = meta:get_int("locked")

	if fields.store then
		local inv = player:get_inventory()
		if inv then
			local n = name
			local wield = player:get_wielded_item()
			if count == 0 and locked == 0 then
				n = wield:get_name()
			end
			local full_stack = ItemStack(n)
			full_stack:set_count(full_stack:get_stack_max())
			local stack = inv:remove_item("main", full_stack)
			while room_for_item(pos, stack) and not stack:is_empty() do
				add_item(pos, stack)
				stack = inv:remove_item("main", full_stack)
			end
			if not stack:is_empty() then
				local left = add_item(pos, stack)
				inv:add_item("main", left)
			end
		end
	end

	if fields.take then
		local inv = player:get_inventory()
		if inv then
			local b = true
			while b do
				b = remove_item(pos, inv, "main", true)
			end
		end
	end

	if fields.lock and name ~= "air" then
		meta:set_int("locked", 1)
		update_infotext(pos)
	end
	if fields.unlock then
		meta:set_int("locked", 0)
		update_infotext(pos)
	end
	if fields.output then
		meta:set_int("output", 1)
		local timer = minetest.get_node_timer(pos)
		timer:start(1.0)
	end
	if fields.stop then meta:set_int("output", 0) end

	if fields.transfer then
		local inv = player:get_inventory()
		local data = { name = name, count = count, locked = locked }
		local item = ItemStack(minetest.get_node(pos).name)
		item:set_metadata(minetest.serialize(data))
		update_description(item, name, count, capacity)

		if inv:room_for_item("main", item) then
			inv:add_item("main", item)
		else
			minetest.add_item(player:getpos(), item)
		end

		minetest.remove_node(pos)
		local obj = find_visual(pos)
		if obj then obj:remove() end
	end
	update_formspec(pos)
end)

-- putting stuff in place

local function on_rightclick(pos, node, clicker, itemstack, pointed_thing)
	if can_access(pos, clicker) then
		if itemstack and not itemstack:is_empty() then
			if clicker:get_player_control().sneak then
				if add_item(pos, ItemStack(itemstack:get_name())):is_empty() then
					itemstack:take_item()
				end
				return itemstack
			else
				return add_item(pos, itemstack)
			end
		else
			local meta = minetest.get_meta(pos)
			local formspec = meta:get_string("showform")
			local formname = "caches:cache"..minetest.pos_to_string(pos)
			minetest.show_formspec(clicker:get_player_name(), formname, formspec)
		end
	end
	return itemstack
end

-- restore proper function to core.item_place for my nodes
-- (so I can actually use the sneak key)

local old_item_place = core.item_place

local function caches_item_place(itemstack, placer, pointed_thing, param2)
	if pointed_thing.type == "node" and placer then
		local n = minetest.get_node(pointed_thing.under)
		local nn = n.name

		if minetest.get_item_group(nn, "caches") > 0 then

			-- need to get the real name and not fake ones
			local i = itemstack:get_name()
			local d = minetest.registered_items[i]
			if d and d.drop then
				-- ignore default items and non-strings
				if type(d.drop) == "string" and not string.match(i, "default:.+") then
					itemstack:set_name(d.drop)
				end
			end
			return on_rightclick(pointed_thing.under, n,
					placer, itemstack, pointed_thing) or itemstack, false
		end
	end

	return old_item_place(itemstack, placer, pointed_thing, param2)
end

core.item_place = caches_item_place

-- handle transfer of meta on crafted upgrades

minetest.register_on_craft(function(itemstack, player, old_craft_grid, craft_inv)
	if minetest.get_item_group(itemstack:get_name(), "caches") > 0 then
		local i = 1
		local craft_size = player:get_inventory():get_size("craft")
		while i <= craft_size do
			local old = old_craft_grid[i]
			i = i + 1
			if minetest.get_item_group(old:get_name(), "caches") > 0 then
				-- copy old cache meta to output stack
				itemstack:set_metadata(old:get_metadata())
				local data = minetest.deserialize(old:get_metadata())
				if data then
					local c = 0
					local n = string.sub(itemstack:get_name(), 8)
					for _, tier in pairs(tiers) do
						if n == tier.name then c = tier.capacity end
					end
					update_description(itemstack, data.name, data.count, c)
				end
				return
			end
		end
	end
end)

-- output a stack below the cache

local function do_output(pos)
	local meta = minetest.get_meta(pos)
	local name = meta:get_string("name")
	local cache_count = meta:get_int("count")

	if cache_count > 0 then
		local count = ItemStack(name):get_stack_max()
		if count > cache_count then count = cache_count end

		local stack = ItemStack(name)
		stack:set_count(count)
		technic.tube_inject_item(pos, pos, vector.new(0, -1, 0), stack)
	
		meta:set_int("count", cache_count - count)
		if cache_count == count and locked == 0 then
			meta:set_string("name", "air")
		end
		update_infotext(pos)
	end
end

-- output mode = do an output once per second

local function cache_node_timer(pos, elapsed)
	local meta = minetest.get_meta(pos)
	local output = meta:get_int("output")
	if output > 0 then
		do_output(pos)
	else
		local timer = minetest.get_node_timer(pos)
		timer:stop()
		return false
	end
	return true
end

-- register item visual

minetest.register_entity("caches:visual", {
	visual = "upright_sprite",
	visual_size = {x=0.6, y=0.6},
	collisionbox = {0},
	physical = false,
	textures = {default_texture},
})

-- register LBM to fix textures in visuals

minetest.register_lbm(
{
	name = "caches:restore_visuals",
	nodenames = {"group:caches"},
	run_at_every_load = true,
	action = function(pos, node)
		update_infotext(pos)
	end,
})

-- register caches

for _, tier in pairs(tiers) do
	minetest.register_node("caches:"..tier.name, {
		description = tier.description,
		groups = { caches=1, tubedevice=1, tubedevice_receiver=1 },
		tiles = { tier.texture },
		paramtype2 = "facedir",
		stack_max = 1,
		tube = {
			insert_object = function(pos, node, stack, direction)
				return add_item(pos, stack)
			end,
			can_insert = function(pos, node, stack, direction)
				return room_for_item(pos, stack)
			end,
			connect_sides = {left=1, right=1, back=1, top=1, bottom=1},
		},
		after_place_node = function(pos, placer, stack)
			local meta = minetest.get_meta(pos)
			local data = minetest.deserialize(stack:get_metadata())
			local name = "air"
			local count = 0
			local locked = 0
			if data then
				name = data.name
				count = data.count
				locked = data.locked
			end
			meta:set_string("name", name)
			meta:set_int("count", count)
			meta:set_int("locked", locked)
			meta:set_int("capacity", tier.capacity)
			update_formspec(pos)
			update_infotext(pos)
			pipeworks.scan_for_tube_objects(pos)
		end,
		after_destruct = function(pos, oldnode)
			pipeworks.scan_for_tube_objects(pos)
		end,
		on_punch = function(pos, node, puncher, pointed_thing)
			if can_access(pos, puncher) then
				local ctrl = puncher:get_player_control()
				local inv = puncher:get_inventory()
				if inv then
					remove_item(pos, inv, "main", not ctrl.sneak)
				end
			end
		end,
		on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
			if itemstack and not itemstack:is_empty() then
				local left = on_rightclick(pos, node, clicker, itemstack, pointed_thing)
				if left:get_count() ~= itemstack:get_count() then
					-- if we're here, this is some custom on_place thing
					-- and this is in the twilight zone
					minetest.after(0.1, function(clicker, left)
						clicker:set_wielded_item(left)
					end, clicker, left)
				end
				return left		-- this value is pointless
			end
		end,
		on_timer = cache_node_timer,
		on_rotate = screwdriver.disallow,
		mesecons = {effector = {action_on = do_output}},

		diggable = false,
		can_dig = function() return false end,
		on_blast = function() end,
	})

	minetest.register_craft({
		output = "caches:"..tier.name,
		recipe = {
			{"", tier.material, ""},
			{tier.material, tier.base, tier.material},
			{"", tier.material, ""},
		}
	})

end
