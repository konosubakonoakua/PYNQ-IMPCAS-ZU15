" ==============================================================================
" The Minimalist Vimrc for Embedded Development
" ==============================================================================

" --- Disable Terminal Flow Control for Ctrl+S ---
" Only run this once during startup to prevent screen blackouts on config reload
if !exists('g:flow_control_disabled') && filereadable('/dev/tty')
    silent !stty -ixon > /dev/null 2>&1
    let g:flow_control_disabled = 1
    redraw!
endif

" --- Version Compatibility Check ---
" Lambda syntax (->) and certain FZF features require Vim 8.1.2048+
let s:min_version = has('patch-8.1.2048') || has('nvim')
if !s:min_version
    echohl WarningMsg
    echo "Warning: Your Vim version is older than 8.1.2048. Some FZF features may fail."
    echohl None
endif

" --- Core Leader Key ---
let mapleader = " "

" --- Define Namespaces (Prefix Protection) ---
" Sets prefixes to <Nop> to act as clean categories and prevent mis-triggers
nnoremap <leader>f <Nop>
nnoremap <leader>s <Nop>
nnoremap <leader>t <Nop>
nnoremap <leader>w <Nop>
nnoremap <leader>c <Nop>
nnoremap <leader>u <Nop>
nnoremap <leader>r <Nop>

" --- Config Management ---
" ev: Edit .vimrc in vertical split
nnoremap <leader>ev :vsplit $HOME/.vimrc<CR>
" sv: Source/Reload .vimrc instantly
nnoremap <leader>sv :source $HOME/.vimrc<CR>:echo "Vimrc successfully reloaded!"<CR>

" --- FZF Core Integration ---
" Dynamically resolve fzf path to allow root sharing
let s:fzf_dir = expand('$HOME/.fzf')
if isdirectory(s:fzf_dir) && executable(s:fzf_dir . '/bin/fzf')
    execute 'set rtp+=' . s:fzf_dir
endif

" --- UI & Display ---
set number              " Show line numbers
set relativenumber      " Show relative line numbers for jumping
set cursorline          " Highlight the current line
set laststatus=2        " Always show status bar
set wildmenu            " Visual autocomplete for command menu
set wildignore=*.docx,*.jpg,*.png,*.gif,*.pdf,*.pyc,*.exe,*.flv,*.img,*.xlsx
set showmatch
set splitbelow    " Horizontal splits open below current
set splitright    " Vertical splits open to the right

if has('unnamedplus')
    set clipboard+=unnamedplus
endif

syntax on
colorscheme koehler
filetype plugin indent on

" --- Storage & Performance (SD Card / Embedded Friendly) ---
set noswapfile          " Disable swap files to reduce SD card wear
set nobackup            " Disable backups
set nowritebackup       " Disable write backups
set hidden              " Allow switching buffers without saving
set updatetime=500      " Faster recovery/plugin response

" --- Search Configuration ---
set hlsearch            " Highlight search results
set incsearch           " Incremental search
set ignorecase          " Case insensitive search...
set smartcase           " ...unless capital letters are used
set path=.,/usr/include,,**3

" --- Global Indentation ---
set expandtab           " Use spaces instead of tabs
set tabstop=4           " 1 tab = 4 spaces
set shiftwidth=4        " Indentation width
set softtabstop=4
set autoindent
set smartindent

" --- Fix ESC Delay ---
set timeoutlen=300      " Faster mapping sequence timeout

" --- Language Specific Overrides ---
" Kernel/DTS style (Hard tabs, 8 width)
autocmd FileType make,dts,dtsi setlocal noexpandtab tabstop=8 shiftwidth=8
" Standard programming style
autocmd FileType python,c,cpp,zig setlocal expandtab tabstop=4 shiftwidth=4
" UI specific
autocmd FileType qf setlocal nowrap

" --- Netrw (File Explorer) ---
let g:netrw_banner = 0        " Hide help banner
let g:netrw_liststyle = 3     " Tree view
let g:netrw_browse_split = 0  " Open file in current window
let g:netrw_altv = 1          " Vertical split to the right
let g:netrw_winsize = 25      " Initial window size
let g:netrw_retmap = 1        " Prevent Netrw from hijacking global keys
let g:netrw_keepdir = 0       " Sync CWD with browsing directory

" ==============================================================================
" Custom Key Mappings & Advanced Features
" ==============================================================================

" --- 1. General & UI Workflow [u] ---
nnoremap <C-s>      :w<CR>
inoremap <C-s> <C-o>:w<CR>
vnoremap <C-s> <C-c>:w<CR>

nnoremap <leader>fw :w<CR>
nnoremap <leader>fe :e<CR>
nnoremap <leader>fr :e!<CR>
nnoremap <leader>uw :set wrap!<CR>
nnoremap <leader>us :if exists("g:syntax_on") <Bar> syntax off <Bar> else <Bar> syntax enable <Bar> endif<CR>
nnoremap <leader>nh :nohlsearch<CR>

" Toggles between Hybrid Mode (Number + RelativeNumber) and No Numbers
function! ToggleLineNumbers()
    if &number || &relativenumber
        set norelativenumber nonumber
    else
        set number relativenumber
    endif
endfunction

nnoremap <leader>un :call ToggleLineNumbers()<CR>
nnoremap <leader>ur :set relativenumber!<CR>

" Double Esc to clear search highlights silently
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

" Quick exit
nnoremap <leader>qq :q<cr>
nnoremap <leader>qa :qa<cr>

" Invisible Characters Visualization
set listchars=tab:▸\ ,trail:·,nbsp:+
nnoremap <leader>ul :set list!<CR>

" --- 2. Native Explorer Mappings [e] ---
nnoremap <leader>e :Lexplore<CR>
nnoremap <leader>st :Vexplore /sys/firmware/devicetree/base<CR>

augroup NetrwCustomMappings
    autocmd!
    autocmd FileType netrw call EnforceNetrwMappings()
    autocmd BufEnter * if &filetype == 'netrw' | call EnforceNetrwMappings() | endif
augroup END

function! EnforceNetrwMappings()
    " Fix split navigation
    silent! nunmap <buffer> <C-l>
    nnoremap <buffer> <nowait> <C-h> <C-w>h
    nnoremap <buffer> <nowait> <C-j> <C-w>j
    nnoremap <buffer> <nowait> <C-k> <C-w>k
    nnoremap <buffer> <nowait> <C-l> <C-w>l

    " Alt-Arrow navigation
    nnoremap <buffer> <nowait> <A-Up>    <C-w>k
    nnoremap <buffer> <nowait> <A-Down>  <C-w>j
    nnoremap <buffer> <nowait> <A-Left>  <C-w>h
    nnoremap <buffer> <nowait> <A-Right> <C-w>l

    " Ranger-style traversal
    nmap <buffer> <nowait> l <CR>
    nmap <buffer> <nowait> L gn
    nnoremap <buffer> <nowait> <silent> h :call NetrwSmartH()<CR>

    " Fast actions
    nnoremap <buffer> <nowait> <leader>v :close<CR>

    " Trigger FZF in directory under cursor
    " Fallback to getcwd() if Netrw variable is missing
    nnoremap <buffer> <nowait> f :FZF <C-R>=get(b:, 'netrw_curdir', getcwd())<CR><CR>
endfunction

" Smart 'h' navigation (logic to jump to parent nodes in tree)
function! NetrwSmartH()
    let l:cur_line = line('.')
    let l:cur_text = getline(l:cur_line)
    let l:cur_indent = match(l:cur_text, '[^| ]')
    if l:cur_indent < 0 | let l:cur_indent = 0 | endif

    " 1. Top level check
    if l:cur_indent == 0 | execute "normal -" | return | endif

    " 2. Open directory check
    let l:is_dir = l:cur_text =~ '/\s*$'
    " FIX: Check if next line exists to avoid out-of-bounds match
    if l:cur_line < line('$')
        let l:next_text = getline(l:cur_line + 1)
        let l:next_indent = match(l:next_text, '[^| ]')
        if l:next_indent > l:cur_indent && l:is_dir
            execute "normal \<CR>"
            return
        endif
    endif

    " 3. Jump to parent
    let l:target_line = l:cur_line - 1
    while l:target_line > 0
        let l:text = getline(l:target_line)
        let l:indent = match(l:text, '[^| ]')
        if l:indent < 0 | let l:indent = 0 | endif
        if l:indent < l:cur_indent
            execute "normal! " . l:target_line . "G"
            return
        endif
        let l:target_line -= 1
    endwhile
    execute "normal -"
endfunction

" --- 3. Find & Search [f / /] ---
nnoremap <leader>ff :FZF<CR>
nnoremap <leader>fb :call fzf#run({'source': map(filter(range(1, bufnr('$')), 'buflisted(v:val)'), 'bufname(v:val)'), 'sink': 'buffer', 'window': 'botright 10split'})<CR>

" Search in user-specified directory
function! FzfInDirectory()
    let l:path = input('Search in directory: ', '', 'dir')
    if l:path !=# ''
        execute 'FZF ' . l:path
    endif
endfunction
nnoremap <leader>fd :call FzfInDirectory()<CR>

" Search Lines in Current Buffer (Replacement for :BLines)
function! FzfLocalLineSearch()
    " Use external 'cat' for saved files (much faster), fallback to getline for new ones
    let l:source = empty(expand('%')) ? getline(1, '$') : 'cat -n ' . expand('%')

    call fzf#run(fzf#wrap({
        \ 'source': l:source,
        \ 'sink': s:min_version ? { line -> execute(matchstr(line, '^\s*\zs\d\+') . 'G') } : 'G',
        \ 'options': '--prompt "Lines> " --preview-window=hidden'
        \ }))
endfunction

" Search active Terminals
function! FzfTerminalSearch()
    let l:terms = filter(range(1, bufnr('$')), 'getbufvar(v:val, "&buftype") ==# "terminal"')
    call fzf#run(fzf#wrap({
        \ 'source': map(l:terms, 'bufname(v:val) . " (" . v:val . ")"'),
        \ 'sink': { line -> execute('buffer ' . matchstr(line, '(\zs\d\+\ze)$')) },
        \ 'options': '--prompt "Terminals> "'
        \ }))
endfunction

" Search Tags (Replacement for :Tags / :BTags)
function! FzfTagSearch(local)
    let l:tags = taglist(a:local ? '^.*' : '.*', expand('%'))
    if empty(l:tags)
        echohl WarningMsg | echo "No tags found. Run <leader>rt to generate." | echohl None
        return
    endif

    " LIMIT: Only process the first 2000 tags to prevent OOM in Kernel sources
    if len(l:tags) > 2000 | let l:tags = l:tags[:2000] | endif

    call fzf#run(fzf#wrap({
        \ 'source': map(l:tags, 'v:val.name . " [" . v:val.kind . "] " . v:val.filename'),
        \ 'sink': s:min_version ? { line -> execute('tag ' . split(line)[0]) } : 'tag',
        \ 'options': '--prompt "' . (a:local ? 'Local' : 'Project') . ' Tags (Max 2000)> "'
        \ }))
endfunction

" Mappings
nnoremap <leader>fl :call FzfLocalLineSearch()<CR>
nnoremap <leader>fz :call FzfTerminalSearch()<CR>
nnoremap <leader>ft :call FzfTagSearch(0)<CR>
nnoremap <leader>fT :call FzfTagSearch(1)<CR>

" --- 4. Split, Buffer & Tab Management [w / b / t] ---
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

nnoremap <silent> <C-Up>    :resize +2<CR>
nnoremap <silent> <C-Down>  :resize -2<CR>
nnoremap <silent> <C-Left>  :vertical resize -2<CR>
nnoremap <silent> <C-Right> :vertical resize +2<CR>

nnoremap <leader>wo <C-w>o
nnoremap <leader>wd <C-w>c

nnoremap <leader>bb :ls<CR>:b<Space>
nnoremap <leader>bn :bnext<CR>
nnoremap <leader>bp :bprevious<CR>
nnoremap <leader>bd :bdelete<CR>

nnoremap <leader>tn :tabnew<CR>
nnoremap <leader>tc :tabclose<CR>
nnoremap <leader>th :tabprevious<CR>
nnoremap <leader>tl :tabnext<CR>

" --- 5. Terminal Operations [t] ---
function! ToggleTerminal(term_idx)
    let l:term_bufs = []
    for b in range(1, bufnr('$'))
        if bufexists(b) && getbufvar(b, '&buftype') ==# 'terminal'
            call add(l:term_bufs, b)
        endif
    endfor

    " Adaptive height based on total screen lines
    let l:pref_height = &lines > 35 ? 15 : 10

    if a:term_idx == 0
        let l:visible_term_win = 0
        for i in range(1, winnr('$'))
            if getwinvar(i, '&buftype') ==# 'terminal'
                let l:visible_term_win = i
                break
            endif
        endfor

        if l:visible_term_win > 0
            execute l:visible_term_win . 'wincmd c'
            return
        else
            if len(l:term_bufs) > 0
                execute 'botright sbuffer ' . l:term_bufs[0]
                execute 'resize ' . l:pref_height
            else
                execute 'botright terminal ++rows=' . l:pref_height . ' ++kill=kill'
            endif
            return
        endif
    endif

    " Clamp index to prevent opening redundant terminals
    let l:target_idx = a:term_idx > (len(l:term_bufs) + 1) ? 0 : a:term_idx

    if l:target_idx > 0 && l:target_idx <= len(l:term_bufs)
        let l:target_buf = l:term_bufs[l:target_idx - 1]
        let l:win_found = bufwinnr(l:target_buf)
        if l:win_found > 0
            execute l:win_found . 'wincmd c'
        else
            execute 'botright sbuffer ' . l:target_buf
            execute 'resize ' . l:pref_height
        endif
    else
        execute 'botright terminal ++rows=' . l:pref_height . ' ++kill=kill'
    endif
endfunction

nnoremap <silent> <C-/> :<C-u>call ToggleTerminal(v:count)<CR>
nnoremap <silent> <C-_> :<C-u>call ToggleTerminal(v:count)<CR>
tnoremap <silent> <C-/> <C-w>c
tnoremap <silent> <C-_> <C-w>c
tnoremap <Esc><Esc> <C-w>N

nnoremap <leader>tt :botright terminal ++rows=15 ++kill=kill<CR>
nnoremap <leader>tv :vert terminal ++cols=50 ++kill=kill<CR>
nnoremap <leader>ts :botright terminal ++rows=15 ++kill=kill picocom -b 115200 /dev/ttyUSB0<CR>
nnoremap <leader>tm :terminal ++hidden ++kill=kill make<CR>

" --- 6. Development Utilities [c / r] ---
function! ToggleQuickfix()
    let l:qf_exists = 0
    for i in range(1, winnr('$'))
        if getwinvar(i, '&buftype') ==# 'quickfix'
            let l:qf_exists = i
            break
        endif
    endfor
    if l:qf_exists > 0
        cclose
    else
        botright copen 10
    endif
endfunction

nnoremap <leader>cq :call ToggleQuickfix()<CR>
nnoremap <leader>cn :cnext<CR>
nnoremap <leader>cp :cprevious<CR>
nnoremap <leader>co :colder<CR>
nnoremap <leader>ci :cnewer<CR>

" Data/Hex utilities
nnoremap <leader>hx :%!xxd<CR>
nnoremap <leader>hr :%!xxd -r<CR>
nnoremap <leader>hb :term xxd %<CR>
nnoremap <leader>rw :%s/\<<c-r><c-w>\>//g<left><left>
nnoremap <leader>rg <cmd>registers<CR>

" Manually clear trailing whitespaces across the file
nnoremap <leader>rs :let _s=@/<Bar>:%s/\s\+$//e<Bar>:let @/=_s<Bar>:nohl<CR>:echo "Trailing whitespaces cleared."<CR>

" Block movement
vnoremap K :m '<-2<CR>gv=gv
vnoremap J :m '>+1<CR>gv=gv

" --- 7. Tag Navigation Settings [t / f] ---
set tags=./tags;,tags;
" tp: Preview tag definition
nnoremap <leader>tp :ptag <C-R><C-W><CR>
" tc: Close preview window
nnoremap <leader>tc :pclose<CR>
" ft: Search Project Tags (FZF)
nnoremap <leader>ft :Tags<CR>
" fT: Search Buffer Tags (FZF)
nnoremap <leader>fT :BTags<CR>
" rt: Re-generate Ctags asynchronously
nnoremap <leader>rt :silent !ctags -R . &<CR>:redraw!<CR>:echo "Tags updating in background..."<CR>

" ==============================================================================
" Hardware & System Inspection [s]
" ==============================================================================
nnoremap <leader>sm :sview /proc/meminfo<CR>
nnoremap <leader>sd :sview /proc/devices<CR>
nnoremap <leader>si :sview /proc/interrupts<CR>
nnoremap <leader>sl :sview /var/log/syslog<CR>
nnoremap <leader>sp :botright terminal ++rows=15 ++kill=kill top<CR>
nnoremap <leader>sk :botright terminal ++rows=10 ++kill=kill dmesg -wH<CR>

" ==============================================================================
" Global Search & Session Management [/ / s]
" ==============================================================================
if executable('rg')
    set grepprg=rg\ --vimgrep\ --no-heading\ --smart-case\ --hidden
    set grepformat=%f:%l:%c:%m,%f:%l:%m
endif

" Search word exactly under cursor
nnoremap <leader>fg :silent grep! "\b<C-R><C-W>\b" .<CR>:copen<CR>:redraw!<CR>

" Interactive Ripgrep search
function! GlobalRgSearch()
    redraw
    let l:query = input('Rg Search: ')
    if l:query !=# ''
        let @/ = l:query
        silent execute 'grep! ' . shellescape(l:query) . ' .'
        copen
        redraw!
    endif
endfunction
nnoremap <silent> <leader>/ :call GlobalRgSearch()<CR>

" Diff tools
nnoremap <leader>dt :diffthis<CR>
nnoremap <leader>do :diffoff<CR>

" ==============================================================================
" Session Management with FZF Integration
" ==============================================================================

" 1. Setup Session Directory
let s:session_dir = expand('$HOME/.vim/sessions')
if !isdirectory(s:session_dir)
    silent! call mkdir(s:session_dir, 'p')
endif

" 2. Save Session (Auto-named by CWD)
function! SaveProjectSession()
    let l:name = substitute(getcwd(), '[\\/:]', '_', 'g') . '.vim'
    execute 'mksession! ' . s:session_dir . '/' . l:name
    echo "Session saved: " . l:name
endfunction

" 3. Load Session (FZF Selector)
function! SelectSession()
    call fzf#run(fzf#wrap({
        \ 'source': 'ls ' . s:session_dir,
        \ 'sink': { line -> execute('source ' . s:session_dir . '/' . line) },
        \ 'options': '--prompt "Load Session> "'
        \ }))
endfunction

" Key Mappings [Prefix: s]
nnoremap <leader>ss :call SaveProjectSession()<CR>
nnoremap <leader>sr :call SelectSession()<CR>

" ==============================================================================
" Quickfix & Special Window Enhancements
" ==============================================================================
augroup SpecialWindows
    autocmd!
    " Auto-close special windows with 'q'
    autocmd FileType qf,help nnoremap <buffer> <nowait> <silent> q :close<CR>
    autocmd FileType qf setlocal nowrap

    " Map 'q' for read-only system information
    autocmd BufReadPost /proc/*,/var/log/* nnoremap <buffer> <nowait> <silent> q :q<CR>

    " Terminal UI cleanup and 'q' support in Normal mode
    if has('nvim')
        autocmd TermOpen * setlocal nonumber norelativenumber nowrap | nnoremap <buffer> <nowait> <silent> q :q!<CR>
    else
        autocmd TerminalOpen * setlocal nonumber norelativenumber nowrap | nnoremap <buffer> <nowait> <silent> q :q!<CR>
    endif

    " Navigation within Quickfix
    autocmd FileType qf nnoremap <buffer> <silent> o <CR><C-w>p
    autocmd FileType qf nnoremap <buffer> <silent> v <C-w><CR><C-w>L<C-w>p
    autocmd FileType qf nnoremap <buffer> <silent> s <C-w><CR><C-w>J<C-w>p
augroup END

" ==============================================================================
" Native Custom Cheat Sheet (Help Menu)
" ==============================================================================
command! CheatSheet call ShowCheatSheet()
nnoremap <leader>H :CheatSheet<CR>

function! ShowCheatSheet()
    let l:bufname = '__CheatSheet__'
    let l:winid = bufwinnr(l:bufname)

    if l:winid != -1
        execute l:winid . "wincmd w"
        return
    endif

    botright 15new
    silent! execute 'file ' . l:bufname
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nowrap modifiable

    let l:help_text = [
    \ "======================================================================",
    \ "              ZynqMP / EZL Workspace Shortcuts (Namespaced)           ",
    \ "======================================================================",
    \ " Leader Key : Space                                                   ",
    \ "",
    \ "--- [u] UI & Workflow ------------------------------------------------",
    \ " <C-s> / <leader>fw  : Save current file                              ",
    \ " <leader>fe / fr     : Edit / Discard & Reload current file           ",
    \ " <leader>qq / qa     : Quit / Quit All                                ",
    \ " <Esc><Esc>          : Clear active search highlight                  ",
    \ " <leader>un / ur     : Toggle Line Numbers (Absolute / Relative)       ",
    \ " <leader>uw / us     : Toggle Line Wrapping / Syntax Highlighting     ",
    \ " <leader>ul          : Toggle Invisible Characters (listchars)        ",
    \ " <leader>ev / sv     : Edit / Source (Hot-reload) .vimrc              ",
    \ " <leader>H           : Show this help menu                            ",
    \ "",
    \ "--- [f] Find & Search ------------------------------------------------",
    \ " <leader>ff / fb     : Find File / Buffer (FZF)                       ",
    \ " <leader>fl          : Find Lines in current buffer (BLines)          ",
    \ " <leader>fz          : Find active Terminals (FZF)                    ",
    \ " <leader>fd          : Find in custom Directory (Prompt for path)     ",
    \ " <leader>ft / fT     : Search Tags (Global / Buffer)                  ",
    \ " <leader>fg          : Global Text Search (Word under cursor)         ",
    \ " <leader>/           : Global Text Search (Prompt for string)         ",
    \ "",
    \ "--- [e] Netrw File Explorer ------------------------------------------",
    \ " <leader>e           : Toggle Project Explorer (Lexplore)             ",
    \ " f (inside Netrw)    : Trigger FZF in current directory               ",
    \ " h / l               : Ranger-style Directory Navigation              ",
    \ " L (Shift-l)         : Enter Directory (Set as new tree root)         ",
    \ " <leader>st          : Explore live Hardware Device Tree (/sys/...)   ",
    \ " <leader>v           : Close current Netrw window                     ",
    \ "",
    \ "--- [w] Window & Buffer ----------------------------------------------",
    \ " <C-h/j/k/l>         : Move between split windows                     ",
    \ " <C-Arrows>          : Resize current window (Up/Down/Left/Right)     ",
    \ " <leader>wo / wd     : Keep Only current window / Close current window",
    \ " <leader>bb          : List and switch buffers                        ",
    \ " <leader>bn / bp     : Next / Previous Buffer                         ",
    \ "",
    \ "--- [t] Terminal & Tabs ----------------------------------------------",
    \ " <C-/>               : Toggle Bottom Terminal (1<C-/>, 2<C-/>)        ",
    \ " <leader>tt / tv     : Open Terminal (Horizontal / Vertical split)    ",
    \ " <leader>ts          : Open UART Console (Picocom /dev/ttyUSB0)       ",
    \ " <leader>tm          : Run 'make' in background (hidden)              ",
    \ " <Esc><Esc>          : Exit Terminal Mode (Back to Normal Mode)       ",
    \ " [Normal Mode] q     : Kill and Close terminal instantly              ",
    \ " <leader>tn / tc     : New Tab / Close Tab                            ",
    \ " <leader>th / tl     : Previous Tab / Next Tab                        ",
    \ "",
    \ "--- [c] Quickfix & [r] Edit ------------------------------------------",
    \ " <leader>cq          : Toggle Quickfix Window                         ",
    \ " <leader>cn / cp     : Jump to Next / Previous result in list         ",
    \ " <leader>co / ci     : Navigate search history (Older / Newer list)   ",
    \ " [Inside QF] q       : Close Quickfix window                          ",
    \ " [Inside QF] o / v / s : Preview / Vertical Split / Horiz Split       ",
    \ " <leader>rw          : Global Replace Word under cursor (in file)     ",
    \ " <leader>rg          : Show Registers                                 ",
    \ " <leader>rs          : Remove trailing whitespaces (Manual)           ",
    \ " Visual K / J        : Move selected block Up / Down                  ",
    \ " <leader>rt          : Re-generate Ctags (Asynchronous)               ",
    \ " <leader>tp / tc     : Tag Preview / Tag Close                        ",
    \ " <leader>hx / hr / hb: Hex Edit / Revert / View Binary                ",
    \ "",
    \ "--- [s] System & Session ---------------------------------------------",
    \ " <leader>sm / sd     : View /proc/meminfo or /proc/devices            ",
    \ " <leader>si / sl     : View /proc/interrupts or /var/log/syslog       ",
    \ " <leader>sk          : Live Kernel Message (dmesg -wH)                ",
    \ " <leader>sp          : Open Process Manager (top)                     ",
    \ " <leader>dt / do     : Diff This / Diff Off                           ",
    \ " <leader>ss          : Save Session (Auto-named by directory)         ",
    \ " <leader>sr          : Select and Load Session (FZF Selector)         ",
    \ "======================================================================",
    \ "                 Press 'q' to close this menu                         "
    \ ]
    call append(0, l:help_text)
    $delete _
    setlocal nomodifiable readonly
    nnoremap <buffer> q :q<CR>
endfunction

" ==============================================================================
" Automated Actions & Performance
" ==============================================================================

" Auto-format Zig files on save
autocmd BufWritePre *.zig silent! :!zig fmt % >/dev/null 2>&1

augroup LargeFile
    autocmd!
    " Disable heavy features for files larger than 2MB
    autocmd BufReadPre * let f=getfsize(expand("<afile>")) | if f > 2097152 | call OptimizeLargeFile() | endif
augroup END

function! OptimizeLargeFile()
    echom "Large file detected: Disabling heavy features."
    setlocal syntax=off nocursorline nowrap nofoldenable undolevels=100
endfunction

" ==============================================================================
" Linux Kernel Coding Style
" ==============================================================================
" Enforcement of Kernel Tabs and 80-character limit
function! s:LinuxKernelStyle()
    setlocal tabstop=8
    setlocal shiftwidth=8
    setlocal softtabstop=8
    setlocal noexpandtab
    setlocal textwidth=80
    match ErrorMsg /\%81v.*/
endfunction

autocmd BufRead,BufNewFile */linux/*,*/kernel/* call s:LinuxKernelStyle()
" Include standard kernel paths for gf (Go to File)
autocmd FileType dts,dtsi setlocal path+=./include,../include,../../include
