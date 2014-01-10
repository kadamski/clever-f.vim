" モードをキーにする辞書で定義
function! clever_f#reset()
    let s:previous_map = {}
    let s:previous_input = {}
    let s:previous_pos = {}
    let s:first_move = {}
    let s:migemo_dicts = {}

    return ""
endfunction

function! clever_f#find_with(map)
    if a:map !~# '^[fFtT]$'
        echoerr 'invalid mapping: ' . a:map
        return
    endif

    let current_pos = getpos('.')[1 : 2]
    let back = 0
    let mode = mode(1)

    if current_pos != get(s:previous_pos, mode, [0, 0])
        " at first step
        if g:clever_f_show_prompt | echon "clever-f: " | endif
        let s:previous_input[mode] = s:get_input(1)
        let s:previous_map[mode] = a:map
        let s:first_move[mode] = 1
        if g:clever_f_show_prompt | redraw! | endif
    else
        " when repeated
        let back = a:map =~# '\u'
    endif

    return clever_f#repeat(back)
endfunction

function! clever_f#repeat(back)
    let mode = mode(1)
    let pmap = get(s:previous_map, mode, "")
    let pinput = get(s:previous_input, mode, '')

    if pmap ==# '' || pinput ==# ''
        return ''
    endif

    if g:clever_f_fix_key_direction ? (! s:first_move[mode] && (pmap =~# '\u' ? !a:back : a:back)) : a:back
        let pmap = s:swapcase(pmap)
    endif

    if mode ==? 'v' || mode ==# "\<C-v>"
        let cmd = s:move_cmd_for_visualmode(pmap, pinput)
    else
        let inclusive = mode ==# 'no' && pmap =~# '\l'
        let cmd = printf("%s:\<C-u>call clever_f#find(%s, %s)\<CR>",
                    \    inclusive ? 'v' : '',
                    \    string(pmap), string(pinput))
    endif

    return cmd
endfunction

function! clever_f#find(map, input)
    let next_pos = s:next_pos(a:map, a:input, v:count1)
    if next_pos != [0, 0]
        let mode = mode(1)
        let s:previous_pos[mode] = next_pos
        call cursor(next_pos[0], next_pos[1])
    endif
endfunction

function! s:move_cmd_for_visualmode(map, input)
    let next_pos = s:next_pos(a:map, a:input, v:count1)
    if next_pos == [0, 0]
        return ''
    endif

    call setpos("''", [0] + next_pos + [0])
    let mode = mode(1)
    let s:previous_pos[mode] = next_pos

    return "``"
endfunction

function! s:get_input(num_strokes)
    let input = ''

    " repeat a:num_strokes times
    for _ in range(a:num_strokes)
        let c = getchar()
        let char = type(c) == type(0) ? nr2char(c) : c
        if char ==# "\<Esc>" || char2nr(char) == 128
            " cancel if escape or special character is input
            return ''
        endif
        let input .= char
    endfor

    return input
endfunction

function! s:search(pat, flag)
    if g:clever_f_across_no_line
        return search(a:pat, a:flag, line('.'))
    else
        return search(a:pat, a:flag)
    endif
endfunction

function! s:should_use_migemo(input)
    if g:clever_f_default_key_strokes != 1
        return 0
    endif

    if ! g:clever_f_use_migemo || a:input !~# '^\a$'
        return 0
    endif

    if ! g:clever_f_across_no_line
        return 1
    endif

    return clever_f#helper#include_multibyte_char(getline('.'))
endfunction

function! s:load_migemo_dict()
    let enc = &l:encoding
    if enc ==# 'utf-8'
        return clever_f#migemo#utf8#load_dict()
    elseif enc ==# 'cp932'
        return clever_f#migemo#cp932#load_dict()
    elseif enc ==# 'euc-jp'
        return clever_f#migemo#eucjp#load_dict()
    else
        let g:clever_f_use_migemo = 0
        throw "Error: ".enc." is not supported. Migemo is made disabled."
    endif
endfunction

function! s:generate_pattern(map, input)
    let input = type(a:input) == type(0) ? nr2char(a:input) : a:input
    let regex = input

    let should_use_migemo = s:should_use_migemo(input)
    if should_use_migemo
        if ! has_key(s:migemo_dicts, &l:encoding)
            let s:migemo_dicts[&l:encoding] = s:load_migemo_dict()
        endif
        let regex = s:migemo_dicts[&l:encoding][regex]
    elseif stridx(g:clever_f_chars_match_any_signs, input) != -1
        " TODO: fix for multi characters
        let regex = '\[!"#$%&''()=~|\-^\\@`[\]{};:+*<>,.?_/]'
    endif

    if a:map ==# 't'
        let regex = '\_.\ze' . regex
    elseif a:map ==# 'T'
        let regex = regex . '\@<=\_.'
    endif

    if ! should_use_migemo
        let regex = '\V'.regex
    endif

    " XXX: fix for multi characters
    return ((g:clever_f_smart_case && input =~# '\l') || g:clever_f_ignore_case ? '\c' : '\C') . regex
endfunction

function! s:next_pos(map, input, count)
    let mode = mode(1)
    let search_flag = a:map =~# '\l' ? 'W' : 'bW'
    let cnt = a:count
    let s:first_move[mode] = 0
    let pattern = s:generate_pattern(a:map, a:input)

    if get(s:first_move, mode, 1)
        if a:map ==? 't'
            if !s:search(pattern, search_flag . 'c')
                return [0, 0]
            endif
            let cnt -= 1
        endif
    endif

    while 0 < cnt
        if !s:search(pattern, search_flag)
            return [0, 0]
        endif
        let cnt -= 1
    endwhile

    return getpos('.')[1 : 2]
endfunction

function! s:swapcase(input)
    return a:input =~# '\u' ? tolower(a:input) : toupper(a:input)
endfunction

call clever_f#reset()
