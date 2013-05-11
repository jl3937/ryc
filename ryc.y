%{
  #include <assert.h>
  #include <stdio.h>
  #include <string.h>
  #include <stdlib.h>
  #include <math.h>
  #include <stdio.h>
  #include "ryc.h"

  int yyerror (char *msg);
  int yylex(void);
  struct nodeType *num(double value);
  struct nodeType *var(const char *name);
  struct nodeType *note(struct nodeType *pitch, struct nodeType *duration);
  struct nodeType *mld(struct nodeType *body, struct nodeType *next);
  struct nodeType *lam(struct nodeType *var, struct nodeType *expr);
  struct nodeType *app(struct nodeType *func, struct nodeType *arg);
  struct nodeType *closure(struct nodeType *def, struct nodeType *env);
  struct nodeType *thunk(struct nodeType *expr, struct nodeType *env);
  struct nodeType *let(struct nodeType *expr, struct nodeType *env);
  struct nodeType *primitive(struct nodeType *name, int n);
  struct nodeType *newEnv(struct nodeType *var, struct nodeType *value);
  struct nodeType *addToEnv(struct nodeType *env, struct nodeType *next);
  void initializePrimitive();
  struct nodeType *lookupEnv(const char *name, nodeType *env);
  struct nodeType *evaluate(struct nodeType *p, struct nodeType *env);
  struct nodeType *apply(struct nodeType *fun,
                         struct nodeType *arg,
                         struct nodeType *env);
  struct nodeType *applyPrimitive(struct nodeType *primitive, nodeType *env);
  struct nodeType *vary(struct nodeType *p, int semitones);
  double timeLength(struct nodeType *p);
  void generateIntermidiateCode();
  void printTree(struct nodeType *expr);
  int gen_midi(struct nodeType *tempo,
               struct nodeType *key,
               struct nodeType *song);
  
  struct nodeType *GlobalEnv = NULL;
  struct nodeType *PrimitiveEnv = NULL;
  struct nodeType *song = NULL;
  struct nodeType *tempo = NULL;
  struct nodeType *key = NULL;
  bool debug = false;
%}

%union {
	double dval;
  char *text;
  struct nodeType *nodp;
}

%token <text> VAR <dval> NUMBER <text> PREFIX SONG KEY TEMPO LET IN LAM DOT
%type <nodp> Program Tempo Key AExpr Expr App AExprList Vars Defn Defns Main Let

%%
Program : Main Defns {
  initializePrimitive();
  GlobalEnv = $2;
  generateIntermidiateCode(); }
        ;
Defns   : { $$ = NULL; }
        | Defn Defns { $$ = addToEnv($1, $2); }
        ;
Defn    : VAR Vars '=' Expr ';' {
            if ($2) {
              struct nodeType * lam = $2;
              while (lam->lam.expr != NULL) {
                lam = lam->lam.expr;
              }
              lam->lam.expr = $4;
              $$ = newEnv(var($1), thunk($2, NULL));
            } else {
              $$ = newEnv(var($1), thunk($4, NULL));
            }
          }
        ;
Vars    : { $$ = NULL; }
        | VAR Vars { $$ = lam(var($1), $2); }
        ;
Main    : Tempo Key SONG '=' Expr ';' { song = $5; }
        ;
Tempo   : { tempo = num(120); }
        | TEMPO '=' Expr ';' { tempo = $3; }
        ;
Key     : { key = num(1); }
        | KEY '=' Expr ';' { key = $3; }
        ;
Expr    : Let App {
          if ($1) {
            /* add head of env list to each thunk's env in env list */
            struct nodeType *env = $1;
            while (env) {
              env->env.value->thunk.env = $1;
              env = env->env.next;
            }
            $$ = let($2, $1);
          } else {
            $$ = $2;
          }
        }
        | LAM VAR DOT Expr { $$ = lam(var($2), $4); }
        ;
App     : AExpr { $$ = $1; }
        | App AExpr { $$ = app($1, $2); }
        ;
Let     : LET Defns IN {
          $$ = $2;
        }
        | { $$ = NULL; }
        ;
AExpr   : VAR { $$ = var($1); }
          /* PREFIX binds tighter with AExpr after it */
        | PREFIX AExpr { $$ = app(var($1), $2); }
          /* note with both pitch and duration specified */
        | '(' Expr ',' Expr ')' { $$ = note($2, $4); }
          /* note with only pitch specified, or a number */
        | NUMBER { $$ = num($1); }
        | '(' Expr ')' { $$ = $2; }
        | '[' AExprList ']' { $2->mld.combineType = seq; $$ = $2; }
        | '{' AExprList '}' { $2->mld.combineType = par; $$ = $2; }
        ;
AExprList : { $$ = mld(NULL, NULL); }
        | '|' { $$ = mld(NULL, NULL); }
        | AExpr AExprList { $$ = mld($1, $2); }
        | '|' AExpr AExprList { $$ = mld($2, $3); }
        ;

%%

struct nodeType *vary(struct nodeType *p, int semitones) {
  switch (p->type) {
    case typeMld:
    {
      struct nodeType *node = p;
      assert(node);
      if (node->mld.body) {
        assert(node->mld.next);
        node->mld.body = vary(node->mld.body, semitones);
        node->mld.next = vary(node->mld.next, semitones);
      }
    }
    break;
    case typeNote:
    {
      vary(p->note.pitch, semitones);
    }
    break;
    case typeNum:
    {
      p->num.vary += semitones;
    }
    break;
    case typeThunk:
    {
      p = vary(evaluate(p->thunk.expr, p->thunk.env), semitones);
    }
    break;
    default:
    {
      fprintf(stderr, "type = %d\n", p->type);
      assert(0);
    }
  }
  return p;
}

double timeLength(struct nodeType *p) {
  switch (p->type) {
    case typeMld:
    {
      int r = 0;
      struct nodeType *node = p;
      while (node && node->mld.body) {
        int length = timeLength(node->mld.body);
        if (node->mld.combineType == seq) {
          r += length;
        } else {
          if (length > r)
            r = length;
        }
        node = node->mld.next;
      }
      return r;
    }
    case typeNote:
    {
      return timeLength(p->note.duration);
    }
    case typeNum:
    {
      return p->num.value;
    }
    default:
    {
      fprintf(stderr, "type = %d\n", p->type);
      assert(0);
    }
  }
}

struct nodeType *num(double value) {
  struct nodeType *p;

  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typeNum;
  p->num.value = value;
  p->num.vary = 0;
  
  return p;
}
struct nodeType *var(const char *name) {
  struct nodeType *p;
  
  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typeVar;
  p->var.name = name;
  
  return p;
}

struct nodeType *note(struct nodeType *pitch, struct nodeType *duration) {
  struct nodeType *p;
  
  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typeNote;
  p->note.pitch = pitch;
  p->note.duration = duration;
  
  return p;
}

struct nodeType *mld(struct nodeType *body, struct nodeType *next) {
  struct nodeType *p;
  
  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typeMld;
  p->mld.body = body;
  p->mld.next = next;
  
  return p;
}

struct nodeType *lam(struct nodeType *var, struct nodeType *expr) {
  struct nodeType *p;
  
  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typeLam;
  p->lam.var = var;
  p->lam.expr = expr;
  
  return p;
}

struct nodeType *app(struct nodeType *func, struct nodeType *arg) {
  struct nodeType *p;
  
  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typeApp;
  p->app.func = func;
  p->app.arg = arg;
  
  return p;
}

struct nodeType *closure(struct nodeType *def, struct nodeType *env) {
  struct nodeType *p;
  
  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typeClosure;
  p->closure.def = def;
  p->closure.env = env;
  
  return p;
}
struct nodeType *thunk(struct nodeType *expr, struct nodeType *env) {
  struct nodeType *p;
  
  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typeThunk;
  p->thunk.expr = expr;
  p->thunk.env = env;
  
  return p;
}

struct nodeType *let(struct nodeType *expr, struct nodeType *env) {
  struct nodeType *p;
  
  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typeLet;
  p->let.expr = expr;
  p->let.env = env;
  
  return p;
}

struct nodeType *primitive(struct nodeType *name, int n) {
  struct nodeType *p;
  
  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typePrimitive;
  p->primitive.name = name;
  p->primitive.argNum = n;
  
  return p;
}

struct nodeType *newEnv(struct nodeType *var, struct nodeType *value) {
  struct nodeType *p;
  
  /* allocate node */
  if ((p = (struct nodeType *)malloc(sizeof(nodeType))) == NULL) {
    printf("out of memory");
    exit(1);
  }
  
  /* copy information */
  p->type = typeEnv;
  p->env.name = var;
  p->env.value = value;
  p->env.next = NULL;
  
  return p;
}

struct nodeType *addToEnv(struct nodeType *env, struct nodeType *next) {
  if (debug)
    printf("addToEnv(%s)\n", env->env.name->var.name);
  env->env.next = next;
  return env;
}

struct nodeType *lookupArg(int i, nodeType *env) {
  char nodeName[20];
  sprintf(nodeName, "a%d", i);
  struct nodeType *arg = lookupEnv(nodeName, env);
  assert(arg);
  assert(arg->type == typeThunk);
  return evaluate(arg->thunk.expr, arg->thunk.env);
}

struct nodeType *applyPrimitive(struct nodeType *primitive, nodeType *env) {
  const char *name = primitive->primitive.name->var.name;
  struct nodeType *args[3];
/*
  if (strcmp(name, "seq") == 0) {
    args[0] = lookupEnv("a0", env);
    assert(args[0]->type == typeThunk);
    if (debug) {
    printTree(args[0]);
    printf("\n[");
    printTree(args[0]->thunk.env);
    printf("]\n");
    }
    args[1] = lookupEnv("a1", env);
    assert(args[1]->type == typeThunk);
    if (debug) {
    printTree(args[1]);
    printf("\n[");
    printTree(args[1]->thunk.env);
    printf("]\n");
    }
    struct nodeType *ans = mld(args[0], args[1]);
    ans->mld.combineType = seq;
    
    return ans;
  } else if (strcmp(name, "par") == 0) {
    args[0] = lookupEnv("a0", env);
    args[1] = lookupEnv("a1", env);
    struct nodeType *ans = mld(args[0], args[1]);
    ans->mld.combineType = par;
    return ans;
  }
 */
  
  args[0] = lookupArg(0, env);
  
  if (strcmp(name, "if") == 0) {
    assert(args[0]->type == typeNum);
    if (args[0]->num.value) {
      return lookupArg(1, env);
    } else {
      return lookupArg(2, env);
    }
  } else if (primitive->primitive.argNum == 1) {
    if (strcmp(name, "not") == 0) {
      return num(!args[0]->num.value);
    } else if (strcmp(name, "note?") == 0) {
      return num(args[0]->type == typeNote || args[0]->type == typeNum);
    } else if (strcmp(name, "seq?") == 0) {
      return num(args[0]->type == typeMld && args[0]->mld.combineType == seq);
    } else if (strcmp(name, "par?") == 0) {
      return num(args[0]->type == typeMld && args[0]->mld.combineType == par);
    } else if (strcmp(name, "nil?") == 0) {
      assert(args[0]->type == typeMld);
      return num(args[0]->mld.body == NULL);
    } else if (strcmp(name, "^") == 0) {
      return vary(args[0], 12);
    } else if (strcmp(name, "_") == 0) {
      return vary(args[0], -12);
    } else if (strcmp(name, "#") == 0) {
      return vary(args[0], 1);
    } else if (strcmp(name, "&") == 0) {
      return vary(args[0], -1);
    } else if (strcmp(name, "car") == 0) {
      assert(args[0]->type == typeMld);
      // args[0]->mld.body = evaluate(args[0]->mld.body, env);
      return args[0]->mld.body;
    } else if (strcmp(name, "cdr") == 0) {
      assert(args[0]->type == typeMld && args[0]->mld.next);
      // args[0]->mld.next = evaluate(args[0]->mld.next, env);
      args[0]->mld.next->mld.combineType = args[0]->mld.combineType;
      return args[0]->mld.next;
    } else if (strcmp(name, "time") == 0) {
      double r = timeLength(args[0]);
      return num(r);
    } else {
      assert(0);
    }
  } else if (primitive->primitive.argNum == 2) {
    if (strcmp(name, "and") == 0 && !args[0]->num.value) {
      return num(0);
    } else if (strcmp(name, "or") == 0 && args[0]->num.value) {
      return num(1);
    }
    args[1] = lookupArg(1, env);
    if (strcmp(name, "+") == 0) {
      struct nodeType *r = num(args[0]->num.value + args[1]->num.value);
      r->num.vary = args[0]->num.vary;
      return r;
    } else if (strcmp(name, "-") == 0) {
      struct nodeType *r = num(args[0]->num.value - args[1]->num.value);
      r->num.vary = args[0]->num.vary;
      return r;
    } else if (strcmp(name, "*") == 0) {
      return num(args[0]->num.value * args[1]->num.value);
    } else if (strcmp(name, "/") == 0) {
      return num(args[0]->num.value / args[1]->num.value);
    } else if (strcmp(name, "%") == 0) {
      return num(fmod(args[0]->num.value, args[1]->num.value));
    } else if (strcmp(name, ">") == 0) {
      bool r = args[0]->num.value > args[1]->num.value;
      if (args[0]->num.value == args[1]->num.value) {
        r = args[0]->num.vary > args[1]->num.vary;
      } else {
        assert(args[0]->num.vary == args[1]->num.vary);
      }
      return num(r);
    } else if (strcmp(name, "<") == 0) {
      bool r = args[0]->num.value < args[1]->num.value;
      if (args[0]->num.value == args[1]->num.value) {
        r = args[0]->num.vary < args[1]->num.vary;
      } else {
        assert(args[0]->num.vary == args[1]->num.vary);
      }
      return num(r);
    } else if (strcmp(name, ">=") == 0) {
      bool r = args[0]->num.value < args[1]->num.value;
      if (args[0]->num.value == args[1]->num.value) {
        r = args[0]->num.vary < args[1]->num.vary;
      } else {
        assert(args[0]->num.vary == args[1]->num.vary);
      }
      return num(!r);
    } else if (strcmp(name, "<=") == 0) {
      bool r = args[0]->num.value > args[1]->num.value;
      if (args[0]->num.value == args[1]->num.value) {
        r = args[0]->num.vary > args[1]->num.vary;
      } else {
        assert(args[0]->num.vary == args[1]->num.vary);
      }
      return num(!r);
    } else if (strcmp(name, "==") == 0) {
      // TODO: add equality test for note, melody
      return num(args[0]->num.value == args[1]->num.value);
    } else if (strcmp(name, "<>") == 0) {
      // TODO: add equality test for note, melody
      return num(args[0]->num.value != args[1]->num.value);
    } else if (strcmp(name, "and") == 0) {
      return num(args[0]->num.value && args[1]->num.value);
    } else if (strcmp(name, "or") == 0) {
      return num(args[0]->num.value || args[1]->num.value);
    } else if (strcmp(name, "seq") == 0) {
      assert(args[1]->type == typeMld && args[1]->mld.combineType == seq);
      if (args[0]->type == typeNum) {
        args[0] = note(args[0], num(1));
      }
      struct nodeType *ans = mld(args[0], args[1]);
      ans->mld.combineType = seq;
      return ans;
    } else if (strcmp(name, "par") == 0) {
      assert(args[1]->type == typeMld && args[1]->mld.combineType == par);
      if (args[0]->type == typeNum) {
        args[0] = note(args[0], num(1));
      }
      struct nodeType *ans = mld(args[0], args[1]);
      ans->mld.combineType = par;
      return ans;
    } else {
      assert(0);
    }
  } else {
    printf("undefined primitive: %s\n", name);
    assert(0);
  }
  return primitive;
}

int main (void) {
	return yyparse();
}

/* Added because panther doesn't have liby.a installed. */
int yyerror (char *msg) {
	return fprintf (stderr, "YACC: %s\n", msg);
}

void initializePrimitive() {
  FILE *fin = fopen("primitive", "r");
  assert(fin);
  char functionName[20];
  int argNum;
  while (fscanf(fin, "%s%d", functionName, &argNum) != EOF) {
    char *name = strdup(functionName);
    struct nodeType *right = primitive(var(name), argNum);
    int i;
    for (i = argNum - 1; i >= 0; --i) {
      char argName[20];
      sprintf(argName, "a%d", i);
      char *arg = strdup(argName);
      struct nodeType *left = var(arg);
      right = lam(left, right);
    }
    
    PrimitiveEnv = addToEnv(newEnv(var(name), thunk(right, NULL)),
                            PrimitiveEnv);
  }
  fclose(fin);
}

void generateIntermidiateCode() {
  /* print AST before evaluation */
  if (debug) {
    printTree(GlobalEnv);
    
    printf("song := ");
    printTree(song);
    printf(";\n");
    
    printf("\n");
  }
  
  /* evaluation */
  song = evaluate(song, NULL);
  tempo = evaluate(tempo, NULL);
  key = evaluate(key, NULL);

  /* print AST after evaluation */
  
  printf("tempo := ");
  printTree(tempo);
  printf(";\n");
  
  printf("key := ");
  printTree(key);
  printf(";\n");
  
  printf("song := ");
  printTree(song);
  printf(";\n");
  
  gen_midi(tempo, key, song);
}

struct nodeType *lookupEnv(const char *name, nodeType *env) {
  /* look up in local environment */
  while (NULL != env) {
    if (strcmp(env->env.name->var.name, name) == 0) {
      return env->env.value;
    } else {
      env = env->env.next;
    }
  }
  
  /* look up in global environment */
  env = GlobalEnv;
  while (NULL != env) {
    if (strcmp(env->env.name->var.name, name) == 0) {
      return env->env.value;
    } else {
      env = env->env.next;
    }
  }
  
  /* look up in primitive environment */
  env = PrimitiveEnv;
  while (NULL != env) {
    if (strcmp(env->env.name->var.name, name) == 0) {
      return env->env.value;
    } else {
      env = env->env.next;
    }
  }
  
  return NULL;
}


struct nodeType *evaluate(struct nodeType *expr, struct nodeType *env) {
  if (!expr)
    return NULL;
  switch (expr->type) {
    case typeMld:
    {
      if (debug) {
        printf("evaluate melody\n");
        printTree(expr);
        printf("\n");
      }

      /* it's safe to malloc a new melody node instead of returning itself */
      struct nodeType *ans = mld(evaluate(expr->mld.body, env),
                                 evaluate(expr->mld.next, env));
      ans->mld.combineType = expr->mld.combineType;
      
      if (ans->mld.body) {
        if (ans->mld.body->type == typeNum) {
          /* as a node of melody, transform number into note */
          // ans->mld.body = note(ans->mld.body, num(1));
        } else if (ans->mld.body->type == typeMld) {
          /* eval body and next for seq */
          /*
          struct nodeType *innerBody = ans->mld.body->mld.body;
          if (innerBody && innerBody->type == typeThunk) {
            ans->mld.body->mld.body = evaluate(innerBody->thunk.expr,
                                               innerBody->thunk.env);
          }
          struct nodeType *innerNext = ans->mld.body->mld.next;
          if (innerNext && innerNext->type == typeThunk) {
            ans->mld.body->mld.next = evaluate(innerNext->thunk.expr,
                                               innerNext->thunk.env);
            assert(ans->mld.body->mld.next->type == typeMld);
            ans->mld.body->mld.next->mld.combineType = expr->mld.combineType;
          }
           */
        }
      }
      
      return ans;
    }
    case typeNote:
    {
      if (debug) {
        printf("evaluate note\n");
        printTree(expr);
        printf("\n");
      }

      return note(evaluate(expr->note.pitch, env),
                  evaluate(expr->note.duration, env));
    }
    case typeNum:
    {
      struct nodeType *ans = num(expr->num.value);
      ans->num.vary = expr->num.vary;
      return ans;
    }
    case typeApp:
    {
      if (debug) {
        printf("evaluate app\n");
        printTree(expr);
        printf("\n");
      }
      
      return apply(expr->app.func, expr->app.arg, env);
    }
    case typeLam:
    {
      if (debug) {
        printf("evaluate lambda\n");
        printTree(expr);
        printf("\n");
      }
      
      return closure(expr, env);
    }
    case typeVar:
    {
      if (debug) {
        printf("evaluate var\n");
        printTree(expr);
        printf("\n");
      }
      
      struct nodeType *value = lookupEnv(expr->var.name, env);
      if (value == NULL) {
        printf("Undefined Variable: %s\n", expr->var.name);
        assert(0);
      } else if (value->type == typeThunk) {
        value = evaluate(value->thunk.expr, value->thunk.env);
      }
      return value;
    }
    case typePrimitive:
    {
      if (debug) {
        printf("evaluate primitive\n");
        printTree(expr);
        printf("\n");
      }

      struct nodeType *ans = applyPrimitive(expr, env);
      return ans;
    }
    case typeLet:
    {
      if (debug) {
        printf("evaluate thunk\n");
        printTree(expr);
        printf("\n");
      }
      
      /* concat env at the end of expr->let.env */
      struct nodeType *localEnv = expr->let.env;
      struct nodeType *newLocalEnv = env;
      while (localEnv) {
        newLocalEnv = addToEnv(newEnv(localEnv->env.name,
                                      thunk(localEnv->env.value->thunk.expr,
                                            NULL)),
                               newLocalEnv);
        localEnv = localEnv->env.next;
      }
      
      struct nodeType *oldEnv = env;
      struct nodeType *env = newLocalEnv;
      while (env != oldEnv) {
        env->env.value->thunk.env = newLocalEnv;
        env = env->env.next;
      }

      struct nodeType *value = evaluate(expr->let.expr, newLocalEnv);
      return value;
    }
    default:
      fprintf(stderr, "type = %d\n", expr->type);
      assert(0);
      break;
  }
  return expr;
}

struct nodeType *apply(struct nodeType *fun,
                       struct nodeType *arg,
                       struct nodeType *env) {
  struct nodeType *ans;

  fun = evaluate(fun, env);
  
  if (fun->type == typeClosure) {
    arg = thunk(arg, env);
    ans = evaluate(fun->closure.def->lam.expr,
                   addToEnv(newEnv(fun->closure.def->lam.var, arg),
                            fun->closure.env));
    
  } else {
    arg = evaluate(arg, env);
    ans = app(fun, arg);
  }
  return ans;
}

void printTree(struct nodeType *expr) {
  if (!expr)
    return;
  if (expr->type == typeMld) {
    if (expr->mld.combineType == seq) {
      printf("[");
    } else {
      printf("{");
    }
    
    struct nodeType *mld = expr;
    while(mld && mld->mld.body) {
      printf(" ");
      
      if (mld->mld.body->type == typeNum) {
        /* as a node of melody, transform number into note */
        mld->mld.body = note(mld->mld.body, num(1));
      }
      printTree(mld->mld.body);
      mld = mld->mld.next;
    }
    
    if (expr->mld.combineType == seq) {
      printf(" ]");
    } else {
      printf(" }");
    }
  } else if (expr->type == typeNote) {
    printf("(");
    printTree(expr->note.pitch);
    printf(", ");
    printTree(expr->note.duration);
    printf(")");
  } else if (expr->type == typeNum) {
    printf("%.1f", expr->num.value);
    if (expr->num.vary > 0)
      printf(" + %d", expr->num.vary);
    else if (expr->num.vary < 0)
      printf(" - %d", 0 - expr->num.vary);
  } else if (expr->type == typeLam) {
    printf("(\\%s -> ", (expr->lam.var)->var.name);
    printTree(expr->lam.expr);
    printf(")");
  } else if (expr->type == typeApp) {
    printf("(");
    printTree(expr->app.func);
    printf(" ");
    printTree(expr->app.arg);
    printf(")");
  } else if (expr->type == typeVar) {
    printf("%s", expr->var.name);
  } else if (expr->type == typePrimitive) {
    printf("\"");
    printf("%s", expr->primitive.name->var.name);
    for (int i = 0; i < expr->primitive.argNum; i++) {
      printf(" a%d", i);
    }
    printf("\"");
  } else if (expr->type == typeEnv) {
    printf("%s := ", expr->env.name->var.name);
    printTree(expr->env.value);
    printf(";\n");
    printTree(expr->env.next);
  } else if (expr->type == typeThunk) {
    printTree(expr->thunk.expr);
  } else if (expr->type == typeLet) {
    printTree(expr->let.expr);
  }
}
