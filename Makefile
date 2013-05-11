CC = g++ -g -Wall
LIBS = -ly -ll -I include -L lib -ljdksmidi
LEX = flex
YACC = yacc
CFLAGS = -DYYDEBUG=1

all: ryc

ryc: ryc.l ryc.y ryc.h gen_midi.h 
	${LEX} ryc.l
	${YACC} -d ryc.y
	${CC} ${CFLAGS} -o ryc y.tab.c lex.yy.c gen_midi.c ${LIBS} -lm

clean:
	rm -f y.tab.c y.tab.h lex.yy.c ryc
	rm -rf ryc.dSYM
