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
}

--- get_metadata
function Source.get_metadata(_)
	return {
		priority = 5000;
		dup = 0;
		menu = '[TN]';
		-- by default, do not sort
		sort = false;
		max_lines = vim.g.compe.source.tabnine.max_line or 1000;
		max_num_results = vim.g.compe.source.tabnine.max_num_results or 20;
	}
end

--- determine
function Source.determine(_, context)
	-- dump(context)
	return compe.helper.determine(context)
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
	args.callback({
		items = nil;
		incomplete = true;
	})
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
	for _, jd in ipairs(data) do
		if jd ~= nil and jd ~= '' then
			local response = json_decode(jd)
			-- dump(response)
			if response == nil then
				-- the _on_exit callback should restart the server
				-- fn.jobstop(Source.job)
				dump('TabNine: json decode error: ', jd)
			elseif #items < Source.get_metadata().max_num_results then
				local results = response.results
				if results ~= nil then
					-- dump(results)
					for _, result in ipairs(results) do
						if #items < Source.get_metadata().max_num_results then
							table.insert(items, result.new_prefix)
						end
					end
				else
					dump('no results:', jd)
				end
			end
		end
	end
	--
	-- now, if we have a callback, send results
	if Source.callback then
		Source.callback({
			items = items;
			-- we are always incomplete.
			incomplete = true;
		})
	end
	Source.callback = nil;
end

Source._on_exit(0, 0)

return Source
