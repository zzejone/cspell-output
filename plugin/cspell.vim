if exists('g:loaded_cspell_plugin')
  finish
endif
let g:loaded_cspell_plugin = 1

lua require('cspell').setup()

" 定義映射示例（可選）
nnoremap <silent> <leader>so :lua require('cspell').check_spelling_and_copy()<CR>
