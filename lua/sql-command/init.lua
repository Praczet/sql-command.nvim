local M = {}
M.config = {
	file_name = ".db.json",
}

local sql_result_buffer = nil
local sql_result_window = nil
local sql_last_position = nil

local function display_result_in_floating_window(result, ismarkdown, database, sql_query)
	-- Split the result into lines to display
	local lines = vim.split(result, "\n")

	-- Calculate maximum width for each column dynamically
	local max_col_widths = {}

	-- Iterate through each line and split by tab
	for _, line in ipairs(lines) do
		local columns = vim.split(line, "\t")

		-- For each column, calculate max width
		for i, col in ipairs(columns) do
			local col_length = vim.fn.strdisplaywidth(col)
			-- Update the max width for the current column if the current length is greater
			if not max_col_widths[i] or col_length > max_col_widths[i] then
				max_col_widths[i] = col_length
			end
		end
	end

	-- Function to pad text to a certain length
	local function pad_text(text, length)
		return text .. string.rep(" ", length - vim.fn.strdisplaywidth(text))
	end

	-- Draw the header (first line)
	local header = lines[1]
	local header_columns = vim.split(header, "\t")
	local formatted_header = "|"

	for i, col in ipairs(header_columns) do
		formatted_header = formatted_header .. " " .. pad_text(col, max_col_widths[i] or 10) .. " |"
	end

	-- Add a separator line after the header (for non-markdown)
	local separator = "+"
	for i = 1, #max_col_widths do
		separator = separator .. string.rep("-", max_col_widths[i] + 2) .. "+"
	end

	-- For markdown tables, create a markdown style separator after the header
	local markdown_separator = "|"
	for i = 1, #max_col_widths do
		markdown_separator = markdown_separator .. string.rep("-", max_col_widths[i]) .. " |"
	end

	-- Format the table content
	local formatted_lines = {}

	-- If rendering as markdown, include the markdown separator
	if ismarkdown then
		-- Add the markdown header
		table.insert(formatted_lines, "# Result from database: " .. database)
		-- Add the SQL fenced code block
		table.insert(formatted_lines, "")
		table.insert(formatted_lines, "```mysql")
		local sql_lines = vim.split(sql_query, "\n")
		if type(sql_lines) == "string" then
			sql_lines = { sql_lines }
		end
		for _, line in ipairs(sql_lines) do
			table.insert(formatted_lines, line)
		end
		table.insert(formatted_lines, "```")
		table.insert(formatted_lines, "")
		-- Add the formatted table
		table.insert(formatted_lines, formatted_header)
		table.insert(formatted_lines, markdown_separator)
	else
		table.insert(formatted_lines, separator)
		table.insert(formatted_lines, formatted_header)
		table.insert(formatted_lines, separator)
	end

	-- Format the content rows
	for i = 2, #lines do
		local row = lines[i]
		if row and row ~= "" then
			local columns = vim.split(row, "\t")
			local formatted_row = "|"
			for j, col in ipairs(columns) do
				formatted_row = formatted_row .. " " .. pad_text(col, max_col_widths[j] or 10) .. " |"
			end
			table.insert(formatted_lines, formatted_row)
		end
	end

	-- Add final separator for non-markdown tables
	if not ismarkdown then
		table.insert(formatted_lines, separator)
	end

	-- Create a new empty buffer for the table

	if sql_result_buffer and vim.api.nvim_buf_is_valid(sql_result_buffer) then
		sql_last_position = vim.fn.getpos(".")
		vim.api.nvim_buf_delete(sql_result_buffer, { force = true })
	end

	sql_result_buffer = vim.api.nvim_create_buf(false, true)

	local win_width = math.floor(vim.o.columns * 0.9)
	local win_height = math.floor(vim.o.lines * 0.9)

	if sql_result_window and vim.api.nvim_win_is_valid(sql_result_window) then
		-- If the window is already open, close it first
		vim.api.nvim_win_close(sql_result_window, true)
	end
	-- Create a floating window to display the table
	sql_result_window = vim.api.nvim_open_win(sql_result_buffer, true, {
		relative = "editor",
		width = win_width,
		height = win_height,
		col = math.floor((vim.o.columns - win_width) / 2),
		row = math.floor((vim.o.lines - win_height) / 2),
		style = "minimal",
		border = "rounded",
	})

	-- Keybindings to close the floating window with 'q' or 'Esc'
	vim.api.nvim_buf_set_keymap(sql_result_buffer, "n", "q", "<Cmd>bd!<CR>", { noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(sql_result_buffer, "n", "<Esc>", "<Cmd>bd!<CR>", { noremap = true, silent = true })

	-- Set the lines of the buffer to the formatted table
	vim.api.nvim_buf_set_lines(sql_result_buffer, 0, -1, false, formatted_lines)

	-- Set the buffer filetype to markdown if `ismarkdown` is true
	if ismarkdown then
		vim.bo[sql_result_buffer].filetype = "markdown"
	end
	vim.wo[sql_result_window].wrap = false
	if sql_last_position then
		vim.fn.setpos(".", sql_last_position)
	end
end

local function read_database_from_file()
	local current_dir = vim.fn.getcwd()
	local json_file = current_dir .. "/" .. M.config.file_name

	-- Check if the file exists
	local file = io.open(json_file, "r")
	if file then
		-- Read the entire file
		local content = file:read("*a")
		file:close()

		-- Parse the JSON content
		local ok, parsed = pcall(vim.fn.json_decode, content)
		if ok and parsed.database then
			return parsed.database
		else
			vim.notify("Error parsing .db.json or missing 'database' entry", vim.log.levels.ERROR)
			return nil
		end
	else
		return nil
	end
end

-- Function to pass the selected text to mariadb with the specified database
local function sql_command(database, opts)
	-- If no argument is passed, try to read from .db.json
	if database == "" then
		local db_from_file = read_database_from_file()
		if db_from_file then
			database = db_from_file
		else
			-- Notify if no database was provided or found in the file
			vim.notify("Warning: No database was given and .db.json not found!", vim.log.levels.WARN)
			return
		end
	end
	-- Get the start and end positions of the visual selection
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local current_line = vim.api.nvim_get_current_line()
	local selected_text = ""

	if opts.range > 0 then
		local lines = vim.fn.getline(start_pos[2], end_pos[2])
		if #lines == 1 then
			lines[1] = string.sub(lines[1], start_pos[3], end_pos[3])
		else
			-- Handle the first line (partial)
			lines[1] = string.sub(lines[1], start_pos[3])
			-- Handle the last line (partial)
			lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
		end
		if type(lines) == "string" then
			lines = { lines }
		end
		selected_text = table.concat(lines, "\n")
	else
		-- No range was passed, fallback to other logic if needed
		selected_text = current_line
	end

	local result = vim.fn.system("mariadb " .. database, selected_text)

	if vim.v.shell_error == 0 then
		display_result_in_floating_window(result, true, database, selected_text)
	else
		vim.notify("Error running SQL command: " .. result, vim.log.levels.ERROR)
	end
end

local function add_sql_command()
	-- Define a user command SQL that takes one argument (the database name)
	vim.api.nvim_create_user_command("SQL", function(opts)
		sql_command(opts.args, opts)
	end, { nargs = "?", range = true })
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	add_sql_command()
end

return M
