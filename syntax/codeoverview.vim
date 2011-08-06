syn clear

if exists("b:current_syntax")
  finish
endif

syn match codeOverviewcomment      /a/
syn match codeOverviewstring       /b/
syn match codeOverviewnormal       /c/
syn match codeOverviewhighlight    /d/
syn match codeOverviewmaj          /e/
syn match codeOverviewempty        /f/
syn match codeOverviewview         /g/
syn match codeOverviewkeyword      /h/
syn match codeOverviewtype         /i/
syn match codeOverviewlabel        /j/
syn match codeOverviewconditional  /k/
syn match codeOverviewrepeat       /l/
syn match codeOverviewstructure    /m/
syn match codeOverviewstatement    /n/
syn match codeOverviewpreproc      /o/
syn match codeOverviewmacro        /p/
syn match codeOverviewtypedef      /q/
syn match codeOverviewexception    /r/
syn match codeOverviewoperator     /s/
syn match codeOverviewinclude      /t/
syn match codeOverviewstorageClass /u/
syn match codeOverviewchar         /v/
syn match codeOverviewnumber       /w/
syn match codeOverviewfloat        /x/
syn match codeOverviewbool         /y/
syn match codeOverviewfunction     /z/

syn match codeOverviewtag          /0/
syn match codeOverviewattribTag    /1/
syn match codeOverviewerror        /2/
syn match codeOverviewwarning      /3/
syn match codeOverviewinfo         /4/

let b:current_syntax = "CodeOverview"

