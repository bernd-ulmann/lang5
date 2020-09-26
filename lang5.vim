" 5 syntax file
" Language:    5
" Maintainer:  Bernd Ulmann <ulmann@vaxman.de>
" Last Change: 22-APR-2011
" Filenames:   *.5
" URL:         http://lang5.sourceforge.net

"
"  To use this syntax highlighting file just add the following three lines to 
" your .vimrc:
"
" syntax on
" au BufRead,BufNewFile *.5 set filetype=5
" au! Syntax 5 source <path_to_this_syntax_file>
"
"  On Mac OS X it might be worthwhile to set the environment variable TERM
" to xterm-color to get real colors displayed in vim. :-)
"

syn match Integer '\<-\=[0-9.]*[0-9.]\+\>'
syn match Integer '\<&-\=[0-9.]*[0-9.]\+\>'
syn match Float '\<-\=\d*[.]\=\d\+[DdEe]\d\+\>'
syn match Float '\<-\=\d*[.]\=\d\+[DdEe][-+]\d\+\>'

syn region CharacterString start=+\.*\"+ end=+"+ end=+$+
syn region CharacterString start=+s\"+ end=+"+ end=+$+
syn region CharacterString start=+c\"+ end=+"+ end=+$+

syn keyword Stack .. .s clear depth drop dup 2dup ndrop over pick _roll roll
syn keyword Stack rot swap

syn keyword Array append apply collapse compress dreduce dress dressed expand
syn keyword Array strip
syn keyword Array extract grade in iota join length outer reduce remove 
syn keyword Array reshape reverse select shape slice split subscript 

syn keyword IO . close eof fin fout open read unlink slurp

syn keyword Operators <=> cmp "||" && ! ?
syn keyword Operators + - * / % ** & | "^"  == != > < >= <=
syn keyword Operators abs amean and choose corr cmean cos defined eq ne gt lt ge le
syn keyword Operators atan2 distinct gmean hmean hoelder inner+ int median neg
syn keyword Operators not or prime qmean sin sqrt subset 
syn keyword Operators min max re im polar complex

syn keyword Control break do loop if else then

syn keyword Misc execute exit gplot help load panic save system type ver 
syn keyword Misc pi e eps

syn keyword VarWord : ; .ofw .v del eval explain set vlist wlist

syn region CommentString start="#" end=+$+

if version >= 508 || !exists("did_5_syn_inits")
    if version < 508
        let did_5_syn_inits = 1
        command -nargs=+ HiLink hi link <args>
    else
        command -nargs=+ HiLink hi def link <args>
    endif

    HiLink Integer Number
    HiLink Float Number
    HiLink CharacterString String
    HiLink Stack Special
    HiLink Array Function
    HiLink IO Statement
    HiLink Operators Operator
    HiLink Control Conditional
    HiLink Misc Define
    HiLink VarWord Debug
    HiLink CommentString Comment

    delcommand HiLink
endif

let b:current_syntax = "5"
