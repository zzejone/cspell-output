local M = {}

-- 檢查 cspell 是否可用
local function check_cspell_available()
  local handle = io.popen("which cspell")
  if handle then
    local result = handle:read("*a")
    handle:close()
    return result ~= ""
  end
  return false
end

-- 獲取當前文件內容
local function get_current_file_content()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return table.concat(lines, "\n")
end

-- 執行 cspell 命令並獲取結果
local function run_cspell(content)
  local cmd = "echo " .. vim.fn.shellescape(content) .. " | cspell --words-only --unique stdin"

  local handle = io.popen(cmd)
  if not handle then
    return nil
  end

  local result = handle:read("*a")
  handle:close()

  return result
end

-- 處理 cspell 輸出，提取未知單詞
local function parse_unknown_words(cspell_output)
  local words = {}

  for word in cspell_output:gmatch("%S+") do
    -- 過濾掉空字符串和只包含符號的單詞
    if word:match("%a") then
      table.insert(words, word)
    end
  end

  return words
end

-- 去重並排序單詞
local function deduplicate_and_sort_words(words)
  local seen = {}
  local unique_words = {}

  for _, word in ipairs(words) do
    if not seen[word] then
      seen[word] = true
      table.insert(unique_words, word)
    end
  end

  table.sort(unique_words)
  return unique_words
end

-- 改進的剪貼板函數，支持 Wayland
local function copy_to_clipboard(text)
  -- 方法 2: 嘗試 Neovim 的剪貼板寄存器
  local ok1 = pcall(function()
    vim.fn.setreg("+", text)
  end)

  if ok1 then
    vim.notify("使用 + 寄存器複製到剪貼板", vim.log.levels.INFO)
    return true
  end

  -- 方法 3: 嘗試使用 "* 寄存器
  local ok2 = pcall(function()
    vim.fn.setreg("*", text)
  end)

  if ok2 then
    vim.notify("使用 * 寄存器複製到剪貼板", vim.log.levels.INFO)
    return true
  end

  -- 方法 4: 使用 xclip (如果可用)
  if vim.fn.executable("xclip") == 1 then
    os.execute("echo " .. vim.fn.shellescape(text) .. " | xclip -selection clipboard")
    vim.notify("使用 xclip 複製到剪貼板", vim.log.levels.INFO)
    return true
  end

  -- 方法 5: 使用 xsel (如果可用)
  if vim.fn.executable("xsel") == 1 then
    os.execute("echo " .. vim.fn.shellescape(text) .. " | xsel --clipboard --input")
    vim.notify("使用 xsel 複製到剪貼板", vim.log.levels.INFO)
    return true
  end

  -- 方法 6: 使用 pbcopy (macOS)
  if vim.fn.has("mac") == 1 then
    os.execute("echo " .. vim.fn.shellescape(text) .. " | pbcopy")
    vim.notify("使用 pbcopy 複製到剪貼板", vim.log.levels.INFO)
    return true
  end

  -- 方法 7: 使用 clip (Windows)
  if vim.fn.has("win32") == 1 then
    os.execute("echo " .. vim.fn.shellescape(text) .. " | clip")
    vim.notify("使用 clip 複製到剪貼板", vim.log.levels.INFO)
    return true
  end

  -- 方法 1: 檢查 Wayland 環境並使用 wl-copy
  if os.getenv("WAYLAND_DISPLAY") then
    if vim.fn.executable("wl-copy") == 1 then
      local handle = io.popen("wl-copy", "w")
      if handle then
        handle:write(text)
        handle:close()
        vim.notify("使用 wl-copy 複製到剪貼板", vim.log.levels.INFO)
        return true
      end
    end
  end

  -- 如果所有方法都失敗，保存到文件
  vim.notify("無法複製到剪貼板，請檢查剪貼板工具安裝", vim.log.levels.WARN)

  -- 作為備用，將內容輸出到臨時文件
  local temp_file = "/tmp/neovim_spell_words.txt"
  local file = io.open(temp_file, "w")
  if file then
    file:write(text)
    file:close()
    vim.notify("單詞已保存到: " .. temp_file, vim.log.levels.INFO)
    return true
  end

  return false
end

-- 主函數：檢查拼寫並複製未知單詞到剪貼板
function M.check_spelling_and_copy()
  -- 檢查 cspell 是否可用
  if not check_cspell_available() then
    vim.notify("cspell 未安裝或不在 PATH 中", vim.log.levels.ERROR)
    return
  end

  -- 保存當前文件（可選）
  if vim.bo.modified then
    vim.cmd("write")
  end

  -- 獲取文件內容
  local content = get_current_file_content()
  if not content or content == "" then
    vim.notify("文件為空", vim.log.levels.WARN)
    return
  end

  -- 執行 cspell
  local cspell_output = run_cspell(content)
  if not cspell_output or cspell_output == "" then
    vim.notify("未找到拼寫錯誤", vim.log.levels.INFO)
    return
  end

  -- 解析結果
  local unknown_words = parse_unknown_words(cspell_output)
  if #unknown_words == 0 then
    vim.notify("未找到拼寫錯誤", vim.log.levels.INFO)
    return
  end

  -- 去重和排序
  local unique_words = deduplicate_and_sort_words(unknown_words)

  -- 格式化輸出
  local output_text = table.concat(unique_words, "\n")

  -- 複製到剪貼板
  local success = copy_to_clipboard(output_text)

  -- 顯示結果
  if success then
    local msg = string.format("找到 %d 個未知單詞，已複製到剪貼板", #unique_words)
    vim.notify(msg, vim.log.levels.INFO)
  end

  -- 在 quickfix 窗口中顯示結果
  local qf_items = {}
  for _, word in ipairs(unique_words) do
    table.insert(qf_items, {
      text = word,
      filename = vim.fn.expand("%:p"),
    })
  end

  vim.fn.setqflist(qf_items, "r")
  vim.cmd("copen")
end

-- 設置命令
function M.setup()
  vim.api.nvim_create_user_command("CSpellCopy", function()
    M.check_spelling_and_copy()
  end, {})
end

return M
