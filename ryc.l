%{
  #include "y.tab.h"
  #include "ryc.h"
  int comment = 0;
  int debug_lex = 0;
%}
number    [0-9]+(\.[0-9]+)?
name      ([a-zA-Z][0-9a-zA-Z'\-\?]*)|\+|\-|\*|\/|\%|\>|\<|\>\=|\<\=|==|\<\>
prefix    \^|_|#|&
%%
\/\*      {comment = 1;}
\*\/      {comment = 0;}
\\        {if (comment == 0) {
  if (debug_lex) printf("\\\n");
  return LAM;}}
->        {if (comment == 0) {
  if (debug_lex) printf("->\n");
  return DOT;}}
song      {if (comment == 0) {
  if (debug_lex) printf("song\n");
  return SONG;}}
key       {if (comment == 0) {
  if (debug_lex) printf("key\n");
  return KEY;}}
tempo     {if (comment == 0) {
  if (debug_lex) printf("tempo\n");
  return TEMPO;}}
let       {if (comment == 0) {
  if (debug_lex) printf("let\n");
  return LET;}}
in        {if (comment == 0) {
  if (debug_lex) printf("in\n");
  return IN;}}
true      {if (comment == 0) {
  if (debug_lex) printf("%s\n", yytext);
  yylval.dval = 1;
  return NUMBER;}}
false     {if (comment == 0) {
  if (debug_lex) printf("%s\n", yytext);
  yylval.dval = 0;
  return NUMBER;}}
{prefix}  {if (comment == 0) {
  if (debug_lex) printf("%s\n", yytext);
  yylval.text = strdup(yytext);
  return PREFIX;
}}
{name}    {if (comment == 0) {
  if (debug_lex) printf("%s\n", yytext);
  yylval.text = strdup(yytext);
  return VAR;}}
{number}  {if (comment == 0) {
  if (debug_lex) printf("%s\n", yytext);
  yylval.dval = atof(yytext);
  return NUMBER;}}
[ \t\n]+  /* ignore whitespace*/;
.         {if (comment == 0) {
  if (debug_lex) printf("%s\n", yytext);
  return yytext[0];}}
%%
