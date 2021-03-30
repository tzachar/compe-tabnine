local compe = require'compe'
local api = vim.api
local fn = vim.fn
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

local Source = {
	callback = nil;
	job = 0;
}

function Source.new(client, source)
  local self = setmetatable({}, { __index = Source })
  self._on_exit(0, 0)
  return self
end


local function istable(t)
	return type(t) == 'table'
end

local function is_enabled()
	if vim.g.compe and vim.g.compe.source and vim.g.compe.source.tabnine then
		return true
	else
		return false
	end
end

local function has_conf(key, default)
	if vim.g.compe and vim.g.compe.source and vim.g.compe.source.tabnine then
		if istable(vim.g.compe.source.tabnine) then
			return vim.g.compe.source.tabnine[key]
		end
	end
	return default
end

--- get_metadata
function Source.get_metadata(_)
	return {
		priority = 5000;
		dup = 0;
		menu = '[TN]';
		-- by default, do not sort
		sort = false;
		max_lines = has_conf('max_line', 1000);
		max_num_results = has_conf('max_num_results', 20);
		show_prediction_strength = has_conf('show_prediction_strength', true);
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
	config = Source.get_metadata()

	local cursor=api.nvim_win_get_cursor(0)
	local cur_line = api.nvim_get_current_line()
	local cur_line_before = string.sub(cur_line, 0, cursor[2])
	local cur_line_after = string.sub(cur_line, cursor[2]+1) -- include current character

	local region_includes_beginning = false
	local region_includes_end = false
	if cursor[1] - config.max_lines <= 1 then region_includes_beginning = true end
	if cursor[1] + config.max_lines >= fn['line']('$') then region_includes_end = true end

	local lines_before = api.nvim_buf_get_lines(0, cursor[1] - config.max_lines , cursor[1]-1, false)
	table.insert(lines_before, cur_line_before)
	local before = table.concat(lines_before, "\n")

	local lines_after = api.nvim_buf_get_lines(0, cursor[1], cursor[1] + config.max_lines, false)
	table.insert(lines_after, 1, cur_line_after)
	local after = table.concat(lines_after, "\n")

	local req = {}
	req.version = "2.0.0"
	req.request = {
		Autocomplete = {
			before = before,
			after = after,
			region_includes_beginning = region_includes_beginning,
			region_includes_end = region_includes_end,
			filename = fn["expand"]("%:p"),
			max_num_results = config.max_num_results
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
  -- api.nvim_put({item.user_data.new_suffix}, "c", true, false)
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
	-- we the first max_num_results. TODO: add sorting and take best max_num_results
	local items = {}
	local old_prefix = ""
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
						table.insert(items, item)
					end
				else
					dump('no results:', jd)
				end
			end
		end
	end

	-- sort by returned importance
	table.sort(items, function(a, b)
		local a_data = 0
		local b_data = 0

		if a.user_data.detail == nil then
			a_data = 0
		else
			a_data = -tonumber(string.sub(a.user_data.detail, 0, -2))
		end

		if b.user_data.detail == nil then
			b_data = 0
		else
			b_data = -tonumber(string.sub(b.user_data.detail, 0, -2))
		end
		return (a_data < b_data)
	end)

	items = {unpack(items, 1, Source.get_metadata().max_num_results)}
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


function Source.documentation(self, args)
	if not Source.get_metadata().show_prediction_strength then
		args.abort()
		return
	end
	local completion_item = args['completed_item']
	if completion_item then
		local result = completion_item['user_data']
		if result.detail then
			args.callback('predicted relevance: **' .. result.detail .. '**')
		else
			args.abort()
		end
	end
end


if is_enabled() then
	return Source.new()
else
	return {}
end
