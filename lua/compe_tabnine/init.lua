local compe = require'compe'
local api = vim.api
local fn = vim.fn
local compe_config = require'compe.config'
--

local function dump(...)
    local objects = vim.tbl_map(vim.inspect, {...})
    print(unpack(objects))
end

local function json_decode(data)
	local status, result = pcall(vim.fn.json_decode, data)
	if status then
		return result
	else
		return nil, result
	end
end

-- locate the binary here, as expand is relative to the calling script name
local binary = nil
if fn.has("mac") == 1 then
	binary = fn.expand("<sfile>:p:h:h:h") .. "/binaries/TabNine_Darwin"
elseif fn.has('unix') == 1 then
	binary = fn.expand("<sfile>:p:h:h:h") .. "/binaries/TabNine_Linux"
else
	binary = fn.expand("<sfile>:p:h:h:h") .. "/binaries/TabNine_Windows"
end

local function is_enabled()
	local conf = compe_config.get()
	return conf.source and conf.source.tabnine and not conf.source.tabnine.disabled
end

local conf_defaults = {
	max_lines = 1000;
	max_num_results = 20;
	sort = true;
	priority = 5000;
	show_prediction_strength = true;
}

-- TODO: consider initializing config once.
local function conf(key)
	local c = compe_config.get()
	if c.source and c.source.tabnine and c.source.tabnine[key] ~= nil then
		return c.source.tabnine[key]
	elseif conf_defaults[key] ~= nil then
		return conf_defaults[key]
	else
		error()
	end
end

local Source = {
	callback = nil;
	job = 0;
}

function Source.new(client, source)
	local self = setmetatable({}, { __index = Source })
	if is_enabled() then
		self._on_exit(0, 0)
	end
	return self
end


--- get_metadata
function Source.get_metadata(_)
	return {
		priority = 5000;
		dup = 0;
		menu = '[TN]';
	}
end

--- determine
function Source.determine(_, context)
	-- dump(context)
	return {
		keyword_pattern_offset = 1;
		trigger_character_offset = context.col;
	}
end

Source._do_complete = function()
	-- print('do complete')
	if Source.job == 0 then
		return
	end
	local max_lines = conf('max_lines')

	local cursor=api.nvim_win_get_cursor(0)
	local cur_line = api.nvim_get_current_line()
	local cur_line_before = string.sub(cur_line, 0, cursor[2])
	local cur_line_after = string.sub(cur_line, cursor[2]+1) -- include current character

	local region_includes_beginning = false
	local region_includes_end = false
	if cursor[1] - max_lines <= 1 then region_includes_beginning = true end
	if cursor[1] + max_lines >= fn['line']('$') then region_includes_end = true end

	local lines_before = api.nvim_buf_get_lines(0, cursor[1] - max_lines , cursor[1]-1, false)
	table.insert(lines_before, cur_line_before)
	local before = table.concat(lines_before, "\n")

	local lines_after = api.nvim_buf_get_lines(0, cursor[1], cursor[1] + max_lines, false)
	table.insert(lines_after, 1, cur_line_after)
	local after = table.concat(lines_after, "\n")

	local req = {}
	req.version = "3.3.0"
	req.request = {
		Autocomplete = {
			before = before,
			after = after,
			region_includes_beginning = region_includes_beginning,
			region_includes_end = region_includes_end,
			filename = fn["expand"]("%:p"),
			max_num_results = conf('max_num_results')
		}
	}

	fn.chansend(Source.job, fn.json_encode(req) .. "\n")
end

--- complete
function Source.complete(self, args)
	Source.callback = args.callback
	Source._do_complete()
end

--- confirm replace suffix
function Source.confirm(self, option)
  local item = option.completed_item

  local pos = api.nvim_win_get_cursor(0)
  local row = pos[1] - 1
  local col = pos[2]
  local len = string.len(item.user_data.old_suffix)
  api.nvim_buf_set_text(0, row, col, row, col+len, {item.user_data.new_suffix})
end


Source._on_err = function(_, data, _)
end

Source._on_exit = function(_, code)
	-- restart..
	if code == 143 then
		-- nvim is exiting. do not restart
		return
	end

	Source.job = fn.jobstart({binary}, {
		on_stderr = Source._on_stderr;
		on_exit = Source._on_exit;
		on_stdout = Source._on_stdout;
	})
end

Source._on_stdout = function(_, data, _)
      -- {
      --   "old_prefix": "wo",
      --   "results": [
      --     {
      --       "new_prefix": "world",
      --       "old_suffix": "",
      --       "new_suffix": "",
      --       "detail": "64%"
      --     }
      --   ],
      --   "user_message": [],
      --   "docs": []
      -- }
	-- dump(data)
	local items = {}
	local old_prefix = ""
	local show_strength = conf('show_prediction_strength')
	local base_priority = conf('priority')

	for _, jd in ipairs(data) do
		if jd ~= nil and jd ~= '' then
			local response = json_decode(jd)
			-- dump(response)
			if response == nil then
				-- the _on_exit callback should restart the server
				-- fn.jobstop(Source.job)
				dump('TabNine: json decode error: ', jd)
			else
				local results = response.results
				old_prefix = response.old_prefix
				if results ~= nil then
					for _, result in ipairs(results) do
						local item = {
							word = result.new_prefix;
							user_data = result;
							filter_text = old_prefix;
						}
						if result.detail ~= nil then
							local percent = tonumber(string.sub(result.detail, 0, -2))
							item['priority'] = base_priority + percent * 0.001
							if show_strength then
								-- abuse kind to show strength
								item['kind'] = result.detail
							end
						end

						table.insert(items, item)
					end
				else
					dump('no results:', jd)
				end
			end
		end
	end

	-- sort by returned importance b4 limiting number of results
	table.sort(items, function(a, b)
		if not a.priority then
			return false
		elseif not b.priority then
			return true
		else
			return (a.priority > b.priority)
		end
	end)

	items = {unpack(items, 1, conf('max_num_results'))}
	--
	-- now, if we have a callback, send results
	if Source.callback then
		if #items == 0 then
			return
		end
		-- update keyword_pattern_offset according to the prefix tabnine reports
		local pos = api.nvim_win_get_cursor(0)
		Source.callback({
			items = items;
			keyword_pattern_offset = pos[2] - #old_prefix + 1;
			incomplete = false;
		})
	end
	Source.callback = nil;
end



return Source.new()
