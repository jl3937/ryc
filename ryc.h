/*
struct envType {
  struct nodeType *name;
  struct nodeType *value;
  struct envType *next;
};
 */

enum nodeEnum {
  typeMld = 0,
  typeNote,
  typeVar,
  typeNum,
  typeLam,
  typeApp,
  typeClosure,
  typeThunk,
  typePrimitive,
  typeEnv,
  typeLet
};

enum combineEnum {
  seq,
  par
};

/* environmrnt */
struct envNodeType {
  struct nodeType *name;
  struct nodeType *value;
  struct nodeType *next;
};

/* moledy */
struct mldNodeType {
  combineEnum combineType;
  struct nodeType *body;
  struct nodeType *next;
};

/* note */
struct noteNodeType {
  struct nodeType *pitch;
  struct nodeType *duration;
};

/* var */
struct varNodeType {
  const char *name;
};

/* number */
struct numNodeType {
  double value;
  int vary;
};

/* function application */
struct appNodeType {
  struct nodeType *func;
  struct nodeType *arg;
};

/* function definition */
struct lamNodeType {
  struct nodeType *var;
  struct nodeType *expr;
};

struct closureNodeType {
  struct nodeType *def;
  struct nodeType *env;
};

struct thunkNodeType {
  struct nodeType *expr;
  struct nodeType *env;
};

struct letNodeType {
  struct nodeType *expr;
  struct nodeType *env;
};

struct primitiveNodeType {
  struct nodeType *name;
  int argNum;
};

struct nodeType {
  nodeEnum type;              /* type of node */
  union {
    mldNodeType mld;
    noteNodeType note;
    varNodeType var;
    numNodeType num;
    lamNodeType lam;
    appNodeType app;
    closureNodeType closure;
    thunkNodeType thunk;
    primitiveNodeType primitive;
    envNodeType env;
    letNodeType let;
  };
};
