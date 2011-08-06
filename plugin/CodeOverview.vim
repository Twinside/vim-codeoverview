"=============================================================================
" What Is This: Launch an helper window to display overview of edited files.
" File: CodeOverview
" Author: Vincent B <twinside@gmail.com>
" Last Change: 2011 Apr 20
" Version: 2.0
if exists("g:__CODEOVERVIEW_VIM__")
    finish
endif
let g:__CODEOVERVIEW_VIM__ = 1

" We try to force text mode
if !has("gui_running")
	" Cannot work if clientserver is not compiled.
	if !has("clientserver")
		finish
    else
        let g:codeOverviewTextMode = 1
    endif
endif

if v:version < 702
    echo 'Your vim version is too old for the CodeOverview plugin, please update it'
    finish
endif

if !exists('g:codeOverviewShowErrorLines')
    let g:codeOverviewShowErrorLines = 1
endif

if !exists("g:code_overview_use_colorscheme")
	let g:code_overview_use_colorscheme = 1
endif

if !exists("g:codeOverviewMaxLineCount")
    let g:codeOverviewMaxLineCount = 10000
endif

if !exists("g:codeOverviewTextMode")
    let g:codeOverviewTextMode = 0
endif

if !exists("g:codeOverviewAsciiSize")
    let g:codeOverviewAsciiSize = 8
endif

if !exists("g:overviewVimServer")
    if !has('gui_running')
        let g:overviewVimServer = 'vim'
    else
        let g:overviewVimServer = 'gvim'
    endif

    let s:uname = substitute(system('uname'), '[\r\n]', '', 'g')
    if has('mac') || s:uname == 'Darwin'
        let g:overviewVimServer = 'mvim'
    endif
endif

" Guard to avoid redrawing when receiving server command
let s:processingServerCommand = 0
let s:preparedParameters = 0
let s:friendProcessStarted = 0
let s:lastQuickfixKind = ''
let s:overviewmode = ''
let s:lastProcessedAsciiFile = ''

if !exists("g:code_overview_ignore_buffer_list")
	let g:code_overview_ignore_buffer_list = []
endif

fun! s:ToggleMode() "{{{
    if s:overviewmode == ''
        let s:overviewmode = '--heatmap'
    else
    	let s:overviewmode = ''
    endif
endfunction "}}}

let s:builtinIgnoreList = [
            \ "__Tag_List__",
            \ "_NERD_tree_",
            \ "NERD_tree_1",
            \ "NERD_tree_2",
            \ "NERD_tree_3",
            \ "Source_Explorer",
            \ "[BuffExplorer]",
            \ "[BufExplorer]",
            \ "Todo List",
            \ "HoogleSearch",
            \ "[fuf]"
            \ ]

let g:code_overview_ignore_buffer_list =
        \ g:code_overview_ignore_buffer_list + s:builtinIgnoreList

fun! ShowCodeOverviewParams() "{{{
    echo 's:tempDir ' . s:tempDir
    echo 's:rmCommand ' . s:rmCommand
    echo 's:tempCommandFile ' . s:tempCommandFile
    echo 's:initPid ' . s:initPid
    echo 's:wakeFile ' . s:wakeFile
    echo 's:tempFile ' . s:tempFile
    echo 's:tempTextFile ' . s:tempTextFile
    echo 's:friendProcess ' . s:friendProcess
    echo 's:overviewProcess ' . s:overviewProcess
    echo 's:colorFile ' . s:colorFile
    echo 's:errFile ' . s:errFile
    echo 's:windowId ' . s:windowId
endfunction "}}}

" Only way to get the correct windowid on unix, is to call gvim
" with the the --echo-wid, redirecting the output somewhere,
fun! s:DefineWindowId() "{{{
	let idFile = '/tmp/vimwinId'
    if has('win32') || has('mac') || !filereadable(idFile)
       let s:windowId = 0
       return
    endif

    for line in readfile(idFile)
    	if line =~ 'WID:'
            let s:windowId = substitute(line, '.*WID: \(\d\+\).*', '\1', '')
            return
        endif
    endfor

    let s:windowId = 0
endfunction "}}}

fun! s:ConvertColorSchemeToColorConf() "{{{
    let colorList = split(globpath( &rtp, 'colors/*.vim' ), '\n')

    for colorFilename in colorList
    	let colorName = substitute(colorFilename, '^.*[\\/]\([^\\\/]\+\)\.vim$', '\1', '')
    	echo "Dumping " . colorName
        highlight clear
    	exe 'color ' . colorName
        call s:BuildColorConfFromColorScheme(colorName . '.color')
    endfor

    highlight clear
    color default
    call s:BuildColorConfFromColorScheme('default.color')
endfunction "}}}

let s:colorConfiguration =
    \ [ ["comment"     , 'comment'     , 'fg']
    \ , ["normal"      , 'normal'      , 'fg']
    \ , ["maj"         , 'normal'      , 'fg']
    \ , ["empty"       , 'normal'      , 'bg']
    \ , ["string"      , 'string'      , 'fg']
    \ , ["keyword"     , 'keyword'     , 'fg']
    \ , ["type"        , 'type'        , 'fg']
    \ , ["view"        , 'cursorline'  , 'bg']
    \ , ["typedef"     , 'Typedef'     , 'fg']
    \ , ["include"     , 'Include'     , 'fg']
    \
    \ , ["conditional" , 'Conditional' , 'fg']
    \ , ["repeat"      , 'Repeat'      , 'fg']
    \ , ["structure"   , 'Structure'   , 'fg']
    \ , ["statement"   , 'Statement'   , 'fg']
    \ , ["preproc"     , 'Preproc'     , 'fg']
    \ , ["exception"   , 'Exception'   , 'fg']
    \ , ["operator"    , 'Operator'    , 'fg']
    \ , ["storageClass", 'StorageClass', 'fg']
    \
    \ , ["float"       , 'Float'       , 'fg']
    \ , ["number"      , 'Number'      , 'fg']
    \ , ["bool"        , 'Boolean'     , 'fg']
    \ , ["char"        , 'Character'   , 'fg']
    \
    \ , ["label"       , 'Label'       , 'fg']
    \ , ["macro"       , 'Macro'       , 'fg']
    \
    \ , ["errorLine"   , 'Error'       , 'bg']
    \ , ["warningLine" , 'Todo'        , 'bg']
    \ , ["infoLine"    , 'IncSearch'   , 'bg']
    \ , ["function"    , 'Function'    , 'fg']
    \ , ["tag"         , 'Statement'   , 'fg']
    \ , ["attribTag"   , 'PreProc'     , 'fg']
    \ ]

fun! s:UpdateColorSchemeForOverview() "{{{
	let normalColor = synIDattr(synIDtrans(hlID("Normal")), 'fg', 'gui')
	let normalTerm = synIDattr(synIDtrans(hlID("Normal")), 'fg', 'cterm')

	for [name, vimAttr, info] in s:colorConfiguration
        let guiColor = synIDattr(synIDtrans(hlID(vimAttr)), info, 'gui')
        let termColor = synIDattr(synIDtrans(hlID(vimAttr)), info, 'cterm')

        if guiColor == ''
        	let guiColor = normalColor
        endif

        let command = 'hi codeOverview' . name 
                    \ . ' guifg=' . guiColor
                    \ . ' guibg=' . guiColor

        if !has('gui_running')
            if termColor == -1
                let termColor = normalTerm
            endif
            let command = command
                    \ . ' ctermbg=' . termColor
                    \ . ' ctermfg=' . termColor
        endif
        execute command
    endfor
endfunction "}}}

" If we want to use the same color as the colorscheme,
" we must prepare a configuration file with some infos.
fun! s:BuildColorConfFromColorScheme(filename) "{{{
    let writtenConf = []

    for [progval, vimAttr, info] in s:colorConfiguration
        let foundColor = synIDattr(synIDtrans(hlID(vimAttr)), info . '#')
        if foundColor != ''
            call add( writtenConf, progval . '=' . foundColor )
        endif
    endfor

    call writefile(writtenConf, a:filename)
endfunction "}}}

fun! s:UpdateColorScheme() "{{{
    call s:BuildColorConfFromColorScheme(s:colorFile)
    call s:UpdateColorSchemeForOverview()
    SnapshotFile
endfunction "}}}

fun! s:PrepareParameters() "{{{
	if s:preparedParameters
        return
    endif

    " Some version of vim don't get globpath with additional
    " flag to avoid wildignore, so we must do it by hand
    let s:tempWildIgnore = &wildignore
    set wildignore=

    if has("win32") || has("win64")
       let s:tempDir = expand("$TEMP") . '\'
       let s:rmCommand = "erase "
       let s:tempCommandFile = s:tempDir . 'command.cmd'
       let s:header = ''
    else
       let s:tempDir = "/tmp/"
       let s:rmCommand = "rm -f "
       let s:tempCommandFile = s:tempDir . 'command.sh'
       let s:header = '#!/bin/sh'
    endif

    let s:initPid = string(getpid())
    let s:wakeFile = s:tempDir . 'overviewFile' . s:initPid . '.txt'
    let s:tempFile = s:tempDir . 'previewer' . s:initPid . '.png'
    let s:tempTextFile = s:tempDir . 'previewer' . s:initPid . '.textcodeoverview'
    let s:colorFile = s:tempDir . 'colorFile' . s:initPid
    let s:errFile = s:tempDir . 'errFile' . s:initPid

    call s:DefineWindowId()

    execute 'set wildignore=' . s:tempWildIgnore

    let s:preparedParameters = 1
endfunction "}}}

fun! s:InitialInit() "{{{
    " Some version of vim don't get globpath with additional
    " flag to avoid wildignore, so we must do it by hand
    let s:tempWildIgnore = &wildignore
    set wildignore=

    if has('win32') || has('win64')
       let s:friendProcess = '"' . globpath( &rtp, 'plugin/WpfOverview.exe' ) . '"'
       let s:overviewProcess = '"' . globpath( &rtp, 'plugin/codeoverview.exe' ) . '"'
    elseif has('unix')
    	let s:uname = substitute(system('uname'), '[\r\n]', '', 'g')
    	if has('mac') || s:uname == 'Darwin'
			let s:friendProcess = '"' . globpath( &rtp, 'plugin/CodeOverMac.app' ) . '"'
			let s:overviewProcess = '"' . globpath( &rtp, 'plugin/codeoverview.osx' ) . '"'
		else
			let s:friendProcess = '"' . globpath( &rtp, 'plugin/gtkOverview.py' ) . '"'
			let s:overviewProcess = '"' . globpath( &rtp, 'plugin/codeoverview' ) . '"'
		endif
    endif

    execute 'set wildignore=' . s:tempWildIgnore
endfunction "}}}

fun! s:RemoveTempsFile() "{{{
    call delete( s:tempFile )
    call delete( s:tempCommandFile )
    call delete( s:errFile )

    if g:code_overview_use_colorscheme
        call delete( s:colorFile )
    endif 
    call delete( s:wakeFile )
endfunction "}}}

fun! s:StopFriendProcess() "{{{
    if s:friendProcessStarted == 0
        echo 'Friend process is already stopped'
        return
    endif

    if !g:codeOverviewTextMode
        call writefile( ["quit"], s:wakeFile )
        let s:friendProcessStarted = 0
    endif

    command! CodeOverviewNoAuto echo 'CodeOverview Friend Process not started!'
    command! CodeOverviewAuto echo 'CodeOverview Friend Process not started!'
    command! SnapshotFile echo 'CodeOverview Friend Process not started!'

    call s:RemoveCodeOverviewHook()
    call s:RemoveTempsFile()
endfunction "}}}

fun! CodeOverviewJumpToBufferLine() "{{{
	let lineNum = line('.') * g:codeOverviewAsciiSize
	let fileWindow = bufwinnr(bufnr(s:lastProcessedAsciiFile))
	exec fileWindow . 'wincmd w'
	exec lineNum
endfunction "}}}

" Set all the option for the code overview buffer, avoid
" modification and put hooks to manage it.
function! s:PrepareCodeOverviewBuffer()
    set ft=NONE
    mapclear <buffer>
    setf	 codeoverview
    setlocal buftype=nofile
    " make sure buffer is deleted when view is closed
    setlocal bufhidden=wipe
    setlocal noswapfile
    setlocal nobuflisted
    setlocal nonumber
    setlocal linebreak
    setlocal foldcolumn=0
    setlocal nocursorline
    setlocal nocursorcolumn
    setlocal autoread
    setlocal nomodifiable

    nnoremap <silent> <buffer> o :call CodeOverviewJumpToBufferLine()<CR>
    nnoremap <silent> <buffer> <LeftRelease> :call CodeOverviewJumpToBufferLine()<CR>
    
    setlocal statusline=[CodeOverview]
endfunction

fun! s:OpenCodeOverviewBuffer() "{{{
	let last_window = winnr()

	vnew
	wincmd L
	vertical resize 20
	exec 'e ' . s:tempTextFile
	call s:PrepareCodeOverviewBuffer()
	exec last_window . 'wincmd w'
endfunction "}}}

fun! s:LaunchAsciiView() "{{{
    let g:codeOverviewTextMode = 1
    call s:LaunchFriendProcess()
endfunction "}}}

" Launch the tracking window for this instance of gVIM
" Configure some script variables used in this script.
fun! s:LaunchFriendProcess() "{{{
    if s:friendProcessStarted == 1
        echo 'Friend process already started'
        return
    endif

    call s:PrepareParameters()

    if g:code_overview_use_colorscheme
        call s:BuildColorConfFromColorScheme(s:colorFile)
    endif

    if exists("g:codeoverview_autoupdate")
        call s:PutCodeOverviewHook()
    endif

    command! CodeOverviewNoAuto call s:RemoveCodeOverviewHook()
    command! CodeOverviewAuto call s:PutCodeOverviewHook()

    if g:codeOverviewTextMode
        call s:UpdateColorSchemeForOverview()
        command! -nargs=? SnapshotFile call s:SnapshotAsciiFile('')
        SnapshotFile
        call s:OpenCodeOverviewBuffer()
        return
    else
        command! -nargs=? SnapshotFile call s:SnapshotFile(<args>)
    endif

    " Just to be sure the file is created
    call writefile( [""], s:wakeFile )
    SnapshotFile

    if has('win32')
        call system('cmd /s /c "start "CodeOverview Launcher" /b '
                \ . s:friendProcess . ' ' . s:initPid . '"')
    elseif has('mac')
        echo 'open -a ' . s:friendProcess . ' -p ' . s:initPid 
        call system('open -a ' . s:friendProcess . ' --args -p ' . s:initPid )
    else
        call system(s:friendProcess . ' ' . s:initPid . ' &')
    endif

    let s:friendProcessStarted = 1

    SnapshotFile

endfunction "}}}

fun! s:SelectClass( kind, error ) "{{{
	if a:kind == 'search'
		return 'i'
    endif

    if a:error =~ '\cwarning'
        return 'w'
    else
        return 'e'
    endif
endfunction "}}}

" Kind could be 'e' for error, 'w' for
" warning 'i' for info...
fun! s:DumpErrorLines(kind) "{{{
	let outLines = []
	let currentBuffer = bufnr('%')

	for d in getqflist()
		if d.bufnr == currentBuffer
            call add(outLines, s:SelectClass(a:kind, d.type) . ':' . string(d.lnum))
        endif
    endfor

    call writefile(outLines, s:errFile)
endfunction "}}}

" This fuction extract data from the current view,
" generate an overview image of the current file,
" write an in an update file readen by the following
" window.
fun! s:SnapshotFile(...) "{{{
	if a:0 > 0
        let kind = a:1
    else
    	let kind = ''
    endif
    if line('$') > g:codeOverviewMaxLineCount
        echo 'File to big, no overview generated'
        return
    endif

    if kind != ''
        let s:lastQuickfixKind = kind
    endif

    if bufname('%') == '' ||
     \ index(g:code_overview_ignore_buffer_list,bufname('%')) >= 0
    	return
    endif

    " If file has been modified, we must dump it somewhere
    if &modified
        let lines = getline( 0, line('$') )
        let filename = s:tempDir . 'tempVimFile' . expand( '%:t' )
        call writefile(lines, filename)
    let filename = '"' . filename . '"'
        let lines = [] " Just to let the garbage collector do it's job.
    else
        let filename = '"' . expand( '%:p' ) . '"'
    endif

    let lastVisibleLine = line('w$')
    let winInfo = winsaveview()
    let research = getreg('/')

    " Generate the new image file
    let commandLine = s:overviewProcess . ' ' . s:overviewmode . ' -v -o "' . s:tempFile . '" ' 

    " If we search an identifier
    if research =~ '\\<.*\\>'
        " Add a switch to let the image generator make it.
        let commandLine = commandLine . ' --hi ' . substitute( research, '\\<\(.*\)\\>', '\1', '' ) . ' '
    endif

    " Dump error lines
    if g:codeOverviewShowErrorLines
    	call s:DumpErrorLines(s:lastQuickfixKind)
    	let commandLine  = commandLine . ' --errfile ' . s:errFile
    endif

    if g:code_overview_use_colorscheme
        let commandLine = commandLine . ' --conf ' . s:colorFile . ' '
    endif

    let commandLine = commandLine . " " . filename

    let wakeText = string(winInfo.topline) 
               \ . '?' . string(lastVisibleLine)
               \ . '?' . synIDattr(synIDtrans(hlID('Normal')), 'bg')
               \ . '?' . synIDattr(synIDtrans(hlID('CursorLine')), 'bg')
               \ . '?' . s:windowId
               \ . '?' . string(getwinposx())
               \ . '?' . string(getwinposy())
               \ . '?' . s:tempFile

    " Make an non-blocking start
    if has('win32')
        let wakeCommand = 'echo ' . wakeText . ' > "' . s:wakeFile . '"'
        let localSwitch = ''
    else
        let wakeCommand = 'echo "' . wakeText . '" > "' . s:wakeFile . '"'
        " Problem arise with mismatch of locale, so set it to a working
        " one
        let localSwitch = 'LC_ALL=en_US.utf8'
    endif

    let commandFile = [ s:header
                    \ , s:rmCommand . '"' . s:tempFile . '"'
                    \ , localSwitch
                    \ , commandLine
                    \ , wakeCommand
                    \ ]

    if &modified
    	call add(commandFile, s:rmCommand . filename )
    endif

    call writefile( commandFile, s:tempCommandFile )

    if has('win32')
        call system( '"' . s:tempCommandFile . '"' )
    else 
    	call system( 'sh "' . s:tempCommandFile . '" &' )
    endif
endfunction "}}}

fun! s:SnapshotAsciiFile(...) "{{{
    if line('$') > g:codeOverviewMaxLineCount
        echo 'File to big, no overview generated'
        return
    endif

    if bufname('%') == '' || &ft == 'codeoverview' ||
     \ index(g:code_overview_ignore_buffer_list,bufname('%')) >= 0 ||
     \ s:processingServerCommand
    	return
    endif

    " If file has been modified, we must dump it somewhere
    if &modified
        let lines = getline( 0, line('$') )
        let filename = s:tempDir . 'tempVimFile' . expand( '%:t' )
        call writefile(lines, filename)
        let filename = '"' . filename . '"'
        let lines = [] " Just to let the garbage collector do it's job.
    else
        let filename = '"' . expand( '%:p' ) . '"'
    endif

    let lastVisibleLine = line('w$')
    let winInfo = winsaveview()
    let research = getreg('/')

    " Generate the new image file
    let commandLine = s:overviewProcess . ' --text=' . g:codeOverviewAsciiSize . ' -v -o "' . s:tempTextFile . '" "'  . filename . '"'
    let callback = g:overviewVimServer . ' --server ' . v:servername . ' --remote-send ":LoadTextOverview<CR>"'

    call writefile([s:header, commandLine, callback], s:tempCommandFile )

    if has('win32')
        exec '!start "' . s:tempCommandFile . '"'
    else 
    	call system( 'sh "' . s:tempCommandFile . '" &' )
    endif
    let s:lastProcessedAsciiFile = bufname('%')
endfunction "}}}

fun! s:PutCodeOverviewHook() "{{{
    augroup CodeOverview
        au BufNewFile * SnapshotFile
        au BufEnter * SnapshotFile
        au BufNew * SnapshotFile
        au BufWritePost * SnapshotFile
        au FilterWritePost * SnapshotFile
        au StdinReadPost * SnapshotFile
        au FileChangedShellPost * SnapshotFile
        au QuickFixCmdPost *grep* SnapshotFile 'search'
        au QuickFixCmdPost *make SnapshotFile 'build'
    augroup END
endfunction "}}}

fun! s:RemoveCodeOverviewHook() "{{{
    augroup CodeOverview
        au!
    augroup END
endfunction "}}}

call s:InitialInit()

command! DumpAllColorSchemes call s:ConvertColorSchemeToColorConf()

if s:friendProcess == '""' || s:overviewProcess == '""'
    echo "Can't find friend executables, aborting CodeOverview load"
    finish
endif

if s:friendProcess =~ "\n" || s:overviewProcess =~ "\n"
    echo "Duplicate installation detected, aborting"
    finish
endif

au VimLeavePre * call s:StopFriendProcess()
au ColorScheme * call s:UpdateColorScheme()

fun! s:LoadTextOverview() "{{{
	if s:processingServerCommand == 1
        return
    endif

    let s:processingServerCommand = 1

	let last_window = winnr()
	let overviewWindow = bufwinnr(bufnr(s:tempTextFile))
	exec overviewWindow . 'wincmd w'
	e
	exec last_window . 'wincmd w'

    let s:processingServerCommand = 0
endfunction "}}}

command! CodeOverviewNoAuto echo 'CodeOverview Friend Process not started!'
command! CodeOverviewAuto echo 'CodeOverview Friend Process not started!'
command! SnapshotFile echo 'CodeOverview Friend Process not started!'
command! ShowCodeOverview call s:LaunchFriendProcess()
command! ShowCodeOverviewAscii call s:LaunchAsciiView()
command! HideCodeOverview call s:StopFriendProcess()
command! ToggleCodeOverview call s:ToggleMode()
command! LoadTextOverview call s:LoadTextOverview()

if exists("g:code_overview_autostart")
	call s:LaunchFriendProcess()
endif

