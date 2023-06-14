/* Please feel free to modify any content */

/* Definition section */
%{
    #include "compiler_common.h" //Extern variables that communicate with lex
    #include "common.h"
    // #define YYDEBUG 1
    // int yydebug = 1;

    extern int yylineno;
    extern int yylex();
    extern FILE *yyin;

    int yylex_destroy ();

    extern int yylineno;
    extern int yylex();
    extern FILE *yyin;

    /* Used to generate code */
    /* As printf; the usage: CODEGEN("%d - %s\n", 100, "Hello world"); */
    /* We do not enforce the use of this macro */
    #define CODEGEN(...) \
        do { \
            for (int i = 0; i < g_indent_cnt; i++) { \
                fprintf(fout, "\t"); \
            } \
            fprintf(fout, __VA_ARGS__); \
        } while (0)

    /* Symbol table function - you can add new functions if needed. */
    /* parameters and return type can be changed */
    static void init_symbol_table();
    static void create_symbol_table();
    static void insert_symbol(char *name, int mut, int type, 
                            int lineno, char *func_sig, int len);
    static struct symbol *lookup_symbol(char *name);
    static void dump_symbol();

    /* Global variables */
    bool g_has_error = false;

    void yyerror (char const *s)
    {
        printf("error:%d: %s\n", yylineno, s);
        g_has_error = true;
    }

    FILE *fout = NULL;
    int g_indent_cnt = 0;

    struct symbol {
        int index;
        char *name;
        bool mut;
        int type;
        int addr;
        int lineno;
        char *func_sig;
        int len; /* only used in array */
    };

    static int fp_count = 0;

    static int geq_label = 0, gt_label = 0, leq_label = 0,
                lt_label = 0, eq_label = 0, neq_label = 0,
                land_label = 0, lor_label = 0, if_label = 0,
                loop_label = 0, for_label = 0, while_label = 0;

    /* 1d array */
    static int array_count = 0;
    static int tmp_1d_array[16] = {0};

    static bool is_range = false;
    static int low = -1;
    static int high = -1;

    #define SYM_TABLE_ROW 6
    #define SYM_TABLE_COL 16
    static struct symbol symbol_table[SYM_TABLE_ROW][SYM_TABLE_COL];
    static int symbol_table_idx[SYM_TABLE_ROW];

    static int global_scope = -1;
    static int addr = -1;

    static int in_what_loop = 0;

    static int break_ret_type = -1;

    static const char *type_table[] = {
        "i32",
        "f32",
        "bool",
        "str",
        "array",
        "void",
        "func"
    };

    static const char type_table_simple[] = {
        'I',
        'F',
        'B',
        'L',
        '[',
        'V',
        'F'
    };

    #define FUNC_SIG_LEN 16

    enum types {
        T_I32,
        T_F32,
        T_BOOL,
        T_STR,
        T_ARRAY_1D,
        T_VOID,
        T_FUNC
    };

    enum {
        NONE,
        IN_LOOP,
        IN_WHILE,
        IN_FOR
    };
%}

%error-verbose

/* Use variable or self-defined structure to represent
 * nonterminal and token type
 *  - you can add new fields if needed.
 */
%union {
    struct {
        union val_union u_val;
        int type;
        struct func_param {
            char *fp_name;
            int fp_type;
        } fp[16];
    } val;
}

/* Token without return */
%token LET MUT NEWLINE
%token INT FLOAT BOOL STR
%token TRUE FALSE
%token GEQ LEQ EQL NEQ LOR LAND
%token ADD_ASSIGN SUB_ASSIGN MUL_ASSIGN DIV_ASSIGN REM_ASSIGN
%token IF ELSE FOR WHILE LOOP
%token PRINT PRINTLN
%token FUNC RETURN BREAK
%token ARROW AS IN DOTDOT RSHIFT LSHIFT

/* Token with return, which need to sepcify type */
%token <val> INT_LIT
%token <val> FLOAT_LIT
%token <val> STRING_LIT ID

/* Nonterminal with return, which need to sepcify type */
%type <val> type name_type parameter_list
%type <val> expression assignment_expression range_expression
            logical_or_expression logical_and_expression rational_expression
            inclusive_or_expression exclusive_or_expression and_expression
            shift_expression additive_expression multiplicative_expression
            casting_expression unary_expression postfix_expression
            primary_expression
%type <val> literal array_initializer_1d compound_statement_function

/* Yacc will start at this nonterminal */
%start program

/* Grammar section */
%%

program
    : global_declaration
    | program global_declaration
;

global_declaration
    : declaration
    | function_definition
;

declaration_list
    : declaration_list declaration
    | declaration
;

declaration
    : LET name_type '=' expression ';' {
        if ($2.type != -1 && $2.type != $4.type)
            yyerror("declaration with different type\n");

        if ($4.type == T_I32) {
            CODEGEN("istore %d\n", addr);
            insert_symbol($2.u_val.s_val, 0, T_I32, 
            yylineno, NULL, 0);
        }
        else if ($4.type == T_F32) {
            CODEGEN("fstore %d\n", addr);
            insert_symbol($2.u_val.s_val, 0, T_F32, 
            yylineno, NULL, 0);
        }
        else if ($4.type == T_STR) {
            CODEGEN("astore %d\n", addr);
            insert_symbol($2.u_val.s_val, 0, T_STR, 
            yylineno, NULL, 0);
        } else if ($4.type == T_BOOL) {
            CODEGEN("istore %d\n", addr);
            insert_symbol($2.u_val.s_val, 0, T_BOOL,
            yylineno, NULL, 0);
        } else if ($4.type == T_ARRAY_1D) {
            /* int[] a = new int[array_count]; */
            CODEGEN("ldc %d\n", array_count);
            CODEGEN("newarray int\n");
            CODEGEN("astore %d\n", addr);

            if (is_range) {
                for (int i = low; i < high; i++) {
                    CODEGEN("aload %d\n", addr);
                    CODEGEN("ldc %d\n", i - low);
                    CODEGEN("ldc %d\n", tmp_1d_array[low]);
                    CODEGEN("iastore\n");
                }
            } else {
                for (int i = 0; i < array_count; i++) {
                    CODEGEN("aload %d\n", addr);
                    CODEGEN("ldc %d\n", i);
                    CODEGEN("ldc %d\n", tmp_1d_array[i]);
                    CODEGEN("iastore\n");
                }
            }

            insert_symbol($2.u_val.s_val, 0, T_ARRAY_1D, 
            yylineno, NULL, array_count);

            is_range = 0;
            array_count = 0;
        }
    }
    | LET MUT name_type '=' expression ';' {
        if ($3.type != -1 && $3.type != $5.type)
            yyerror("declaration with different type\n");

        if ($5.type == T_I32) {
            CODEGEN("istore %d\n", addr);
            insert_symbol($3.u_val.s_val, 1, T_I32, 
            yylineno, NULL, 0);
        } else if ($5.type == T_F32) {
            CODEGEN("fstore %d\n", addr);
            insert_symbol($3.u_val.s_val, 1, T_F32, 
            yylineno, NULL, 0);
        } else if ($5.type == T_STR) {
            CODEGEN("astore %d\n", addr);
            insert_symbol($3.u_val.s_val, 1, T_STR, 
            yylineno, NULL, 0);
        } else if ($5.type == T_BOOL) {
            CODEGEN("istore %d\n", addr);
            insert_symbol($3.u_val.s_val, 1, T_BOOL,
            yylineno, NULL, 0);
        } else if ($5.type == T_ARRAY_1D) {
            /* int[] a = new int[array_count]; */
            CODEGEN("ldc %d\n", array_count);
            CODEGEN("anewarray int\n");
            CODEGEN("astore %d\n", addr);

            if (is_range) {
                for (int i = low; i < high; i++) {
                    CODEGEN("aload %d\n", addr);
                    CODEGEN("ldc %d\n", i - low);
                    CODEGEN("ldc %d\n", tmp_1d_array[low]);
                    CODEGEN("aastore\n");
                }
            } else {
                for (int i = 0; i < array_count; i++) {
                    CODEGEN("aload %d\n", addr);
                    CODEGEN("ldc %d\n", i);
                    CODEGEN("ldc %d\n", tmp_1d_array[i]);
                    CODEGEN("aastore\n");
                }
            }

            insert_symbol($3.u_val.s_val, 1, T_ARRAY_1D, 
            yylineno, NULL, array_count);

            is_range = 0;
            array_count = 0;
        }
    }
    | LET name_type ';' {
        insert_symbol($2.u_val.s_val, 0, $2.type,
            yylineno, NULL, 0);
    }
    | LET MUT name_type ';' {
        insert_symbol($3.u_val.s_val, 1, $3.type, 
            yylineno, NULL, 0);
    }
;

name_type
    : ID            { 
        $$.u_val.s_val = $1.u_val.s_val; 
        $$.type = -1;
    }
    | ID ':' type   { 
        $$.u_val.s_val = $1.u_val.s_val;
        $$.type = $3.type;
    }
;

type
    : INT           { $$.type = T_I32; }
    | FLOAT         { $$.type = T_F32; }
    | BOOL          { $$.type = T_BOOL; }
    | '&' STR       { $$.type = T_STR; }
    | array_type    { $$.type = T_ARRAY_1D; }
;

array_type
    : '[' array_type ';' INT_LIT ']'
    | simple_type
;

simple_type
    : INT
    | FLOAT
    | BOOL
    | '&' STR
;

expression
    : assignment_expression {
        $$.type = $1.type;
    }
;

assignment_expression
    : ID '=' assignment_expression {
        struct symbol *sym = lookup_symbol($1.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $1.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        if (sym->type != $3.type)
            yyerror("operands in assignment must have same type\n");

        int local_addr = sym->addr;

        if ($3.type == T_I32 || $3.type == T_BOOL)
            CODEGEN("istore %d\n", local_addr);
        else if ($3.type == T_F32)
            CODEGEN("fstore %d\n", local_addr);
        else if ($3.type == T_STR)
            CODEGEN("astore %d\n", local_addr);
        else
            yyerror("assignment not support this type\n");
    }
    | ID ADD_ASSIGN assignment_expression {
        struct symbol *sym = lookup_symbol($1.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $1.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        if (sym->type != $3.type)
            yyerror("operands in assignment must have same type\n");

        int local_addr = sym->addr;

        if ($3.type == T_I32) {
            CODEGEN("iload %d\n", local_addr);
            CODEGEN("iadd\n");
            CODEGEN("istore %d\n", local_addr);
        } else if ($3.type == T_F32) {
            CODEGEN("fload %d\n", local_addr);
            CODEGEN("fadd\n");
            CODEGEN("fstore %d\n", local_addr);
        } else
            yyerror("assignment not support this type\n");
    }
    | ID SUB_ASSIGN assignment_expression {
        struct symbol *sym = lookup_symbol($1.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $1.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        if (sym->type != $3.type)
            yyerror("operands in assignment must have same type\n");

        int local_addr = sym->addr;

        if ($3.type == T_I32) {
            CODEGEN("iload %d\n", local_addr);
            CODEGEN("swap\n");
            CODEGEN("isub\n");
            CODEGEN("istore %d\n", local_addr);
        } else if ($3.type == T_F32) {
            CODEGEN("fload %d\n", local_addr);
            CODEGEN("swap\n");
            CODEGEN("fsub\n");
            CODEGEN("fstore %d\n", local_addr);
        } else
            yyerror("assignment not support this type\n");
    }
    | ID MUL_ASSIGN assignment_expression {
        struct symbol *sym = lookup_symbol($1.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $1.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        if (sym->type != $3.type)
            yyerror("operands in assignment must have same type\n");

        int local_addr = sym->addr;

        if ($3.type == T_I32) {
            CODEGEN("iload %d\n", local_addr);
            CODEGEN("imul\n");
            CODEGEN("istore %d\n", local_addr);
        } else if ($3.type == T_F32) {
            CODEGEN("fload %d\n", local_addr);
            CODEGEN("fmul\n");
            CODEGEN("fstore %d\n", local_addr);
        } else
            yyerror("assignment not support this type\n");
    }
    | ID DIV_ASSIGN assignment_expression {
        struct symbol *sym = lookup_symbol($1.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $1.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        if (sym->type != $3.type)
            yyerror("operands in assignment must have same type\n");

        int local_addr = sym->addr;

        if ($3.type == T_I32) {
            CODEGEN("iload %d\n", local_addr);
            CODEGEN("swap\n");
            CODEGEN("idiv\n");
            CODEGEN("istore %d\n", local_addr);
        } else if ($3.type == T_F32) {
            CODEGEN("fload %d\n", local_addr);
            CODEGEN("swap\n");
            CODEGEN("fdiv\n");
            CODEGEN("fstore %d\n", local_addr);
        } else
            yyerror("assignment not support this type\n");
    }
    | ID REM_ASSIGN assignment_expression {
        struct symbol *sym = lookup_symbol($1.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $1.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        if (sym->type != $3.type)
            yyerror("operands in assignment must have same type\n");

        int local_addr = sym->addr;

        if ($3.type == T_I32) {
            CODEGEN("iload %d\n", local_addr);
            CODEGEN("swap\n");
            CODEGEN("irem\n");
            CODEGEN("istore %d\n", local_addr);
        } else if ($3.type == T_F32) {
            CODEGEN("fload %d\n", local_addr);
            CODEGEN("swap\n");
            CODEGEN("frem\n");
            CODEGEN("fstore %d\n", local_addr);
        } else
            yyerror("assignment not support this type\n");
    }
    | range_expression {
        $$.type = $1.type;
    }
;

assignment_operator
    : '='
    | ADD_ASSIGN
    | SUB_ASSIGN
    | MUL_ASSIGN
    | DIV_ASSIGN
    | REM_ASSIGN
;

range_expression
    : INT_LIT DOTDOT {
        is_range = true;
        low = $1.u_val.i_val;
        high = array_count - 1;

        $$.type = T_ARRAY_1D;
    }
    | DOTDOT INT_LIT {
        is_range = true;
        low = 0;
        high = $2.u_val.i_val - 1;

        $$.type = T_ARRAY_1D;
    }
    | INT_LIT DOTDOT INT_LIT {
        is_range = true;
        low = $1.u_val.i_val;
        high = $3.u_val.i_val - 1;

        $$.type = T_ARRAY_1D;
    }
    | logical_or_expression {
        $$.type = $1.type;
    }
;

logical_or_expression
    : logical_or_expression LOR logical_and_expression {
        CODEGEN("ldc 0\n");
        CODEGEN("if_icmpne l_lor_first_success_%d\n", lor_label);
        CODEGEN("ldc 0\n");
        CODEGEN("if_icmpne l_lor_success_%d\n", lor_label);
        CODEGEN("ldc 0\n");
        CODEGEN("goto l_lor_finish_%d\n", lor_label);
        g_indent_cnt = 0;
        CODEGEN("l_lor_first_success_%d:\n", lor_label);
        g_indent_cnt = 1;
        CODEGEN("pop\n");
        g_indent_cnt = 0;
        CODEGEN("l_lor_success_%d:\n", lor_label);
        g_indent_cnt = 1;
        CODEGEN("ldc 1\n");
        g_indent_cnt = 0;
        CODEGEN("l_lor_finish_%d:\n", lor_label);
        g_indent_cnt = 1;

        lor_label++;

        $$.type = T_BOOL;
    }
    | logical_and_expression {
        $$.type = $1.type;
    }
;

logical_and_expression
    : logical_and_expression LAND rational_expression {
        CODEGEN("ldc 0\n");
        CODEGEN("if_icmpne l_land_first_success_%d\n", land_label);
        CODEGEN("pop\n");
        CODEGEN("ldc 0\n");
        CODEGEN("goto l_land_finish_%d\n", land_label);
        g_indent_cnt = 0;
        CODEGEN("l_land_first_success_%d:\n", land_label);
        g_indent_cnt = 1;
        CODEGEN("ldc 0\n");
        CODEGEN("if_icmpne l_land_success_%d\n", land_label);
        CODEGEN("ldc 0\n");
        CODEGEN("goto l_land_finish_%d\n", land_label);
        g_indent_cnt = 0;
        CODEGEN("l_land_success_%d:\n", land_label);
        g_indent_cnt = 1;
        CODEGEN("ldc 1\n");
        g_indent_cnt = 0;
        CODEGEN("l_land_finish_%d:\n", land_label);
        g_indent_cnt = 1;

        land_label++;

        $$.type = T_BOOL;
    }
    | rational_expression {
        $$.type = $1.type;
    }
;

rational_expression
    : rational_expression GEQ inclusive_or_expression {
        if ($1.type != $3.type)
            yyerror("operands in >= must be same type\n");

        if ($1.type == T_I32 || $1.type == T_BOOL)
            CODEGEN("isub\n");
        else if ($1.type == T_F32) {
            CODEGEN("fsub\n");
            CODEGEN("f2i\n");
        }

        CODEGEN("ifge l_geq_%d\n", geq_label);
        CODEGEN("ldc 0\n"); // not >=
        CODEGEN("goto l_geq_finished_%d\n", geq_label);
        g_indent_cnt = 0;
        CODEGEN("l_geq_%d:\n", geq_label);
        g_indent_cnt = 1;
        CODEGEN("ldc 1\n");
        g_indent_cnt = 0;
        CODEGEN("l_geq_finished_%d:\n", geq_label);
        g_indent_cnt = 1;

        geq_label++;

        $$.type = T_BOOL;
    }
    | rational_expression LEQ inclusive_or_expression {
        if ($1.type != $3.type)
            yyerror("operands in <= must be same type\n");

        if ($1.type == T_I32 || $1.type == T_BOOL)
            CODEGEN("isub\n");
        else if ($1.type == T_F32) {
            CODEGEN("fsub\n");
            CODEGEN("f2i\n");
        }

        CODEGEN("ifle l_leq_%d\n", leq_label);
        CODEGEN("ldc 0\n"); // not <=
        CODEGEN("goto l_leq_finished_%d\n", leq_label);
        g_indent_cnt = 0;
        CODEGEN("l_leq_%d:\n", leq_label);
        g_indent_cnt = 1;
        CODEGEN("ldc 1\n");
        g_indent_cnt = 0;
        CODEGEN("l_leq_finished_%d:\n", leq_label);
        g_indent_cnt = 1;

        leq_label++;

        $$.type = T_BOOL;
    }
    | rational_expression EQL inclusive_or_expression {
        if ($1.type != $3.type)
            yyerror("operands in == must be same type\n");

        if ($1.type == T_I32 || $1.type == T_BOOL)
            CODEGEN("isub\n");
        else if ($1.type == T_F32) {
            CODEGEN("fsub\n");
            CODEGEN("f2i\n");
        }

        CODEGEN("ifeq l_eq_%d\n", eq_label);
        CODEGEN("ldc 0\n"); // not ==
        CODEGEN("goto l_eq_finished_%d\n", eq_label);
        g_indent_cnt = 0;
        CODEGEN("l_eq_%d:\n", eq_label);
        g_indent_cnt = 1;
        CODEGEN("ldc 1\n");
        g_indent_cnt = 0;
        CODEGEN("l_eq_finished_%d:\n", eq_label);
        g_indent_cnt = 1;

        eq_label++;

        $$.type = T_BOOL;
    }
    | rational_expression NEQ inclusive_or_expression {
        if ($1.type != $3.type)
            yyerror("operands in != must be same type\n");

        if ($1.type == T_I32 || $1.type == T_BOOL)
            CODEGEN("isub\n");
        else if ($1.type == T_F32) {
            CODEGEN("fsub\n");
            CODEGEN("f2i\n");
        }

        CODEGEN("ifne l_neq_%d\n", neq_label);
        CODEGEN("ldc 0\n"); // not !=
        CODEGEN("goto l_neq_finished_%d\n", neq_label);
        g_indent_cnt = 0;
        CODEGEN("l_neq_%d:\n", neq_label);
        g_indent_cnt = 1;
        CODEGEN("ldc 1\n");
        g_indent_cnt = 0;
        CODEGEN("l_neq_finished_%d:\n", neq_label);
        g_indent_cnt = 1;

        neq_label++;

        $$.type = T_BOOL;
    }
    | rational_expression '>' inclusive_or_expression {
        if ($1.type != $3.type)
            yyerror("operands in > must be same type\n");

        if ($1.type == T_I32 || $1.type == T_BOOL)
            CODEGEN("isub\n");
        else if ($1.type == T_F32) {
            CODEGEN("fsub\n");
            CODEGEN("f2i\n");
        }

        CODEGEN("ifgt l_gt_%d\n", gt_label);
        CODEGEN("ldc 0\n"); // not >
        CODEGEN("goto l_gt_finished_%d\n", gt_label);
        g_indent_cnt = 0;
        CODEGEN("l_gt_%d:\n", gt_label);
        g_indent_cnt = 1;
        CODEGEN("ldc 1\n");
        g_indent_cnt = 0;
        CODEGEN("l_gt_finished_%d:\n", gt_label);
        g_indent_cnt = 1;

        gt_label++;

        $$.type = T_BOOL;
    }
    | rational_expression '<' inclusive_or_expression {
        if ($1.type != $3.type)
            yyerror("operands in < must be same type\n");

        if ($1.type == T_I32 || $1.type == T_BOOL)
            CODEGEN("isub\n");
        else if ($1.type == T_F32) {
            CODEGEN("fsub\n");
            CODEGEN("f2i\n");
        }

        CODEGEN("iflt l_lt_%d\n", lt_label);
        CODEGEN("ldc 0\n"); // not <
        CODEGEN("goto l_lt_finished_%d\n", lt_label);
        g_indent_cnt = 0;
        CODEGEN("l_lt_%d:\n", lt_label);
        g_indent_cnt = 1;
        CODEGEN("ldc 1\n");
        g_indent_cnt = 0;
        CODEGEN("l_lt_finished_%d:\n", lt_label);
        g_indent_cnt = 1;

        lt_label++;

        $$.type = T_BOOL;
    }
    | inclusive_or_expression {
        $$.type = $1.type;
    }
;

inclusive_or_expression
    : inclusive_or_expression '|' exclusive_or_expression {
        if ($1.type != T_I32  && 
            $1.type != T_BOOL &&
            $3.type != T_I32  &&
            $3.type != T_BOOL)
            yyerror("operands in ior must be integer or bool\n");

        CODEGEN("ior\n");

        $$.type = $1.type;
    }
    | exclusive_or_expression {
        $$.type = $1.type;
    }
;

exclusive_or_expression
    : exclusive_or_expression '^' and_expression {
        if ($1.type != T_I32  && 
            $1.type != T_BOOL &&
            $3.type != T_I32  &&
            $3.type != T_BOOL)
            yyerror("operands in xor must be integer or bool\n");

        CODEGEN("ixor\n");

        $$.type = $1.type;
    }
    | and_expression {
        $$.type = $1.type;
    }
;

and_expression
    : and_expression '&' shift_expression {
        if ($1.type != T_I32  && 
            $1.type != T_BOOL &&
            $3.type != T_I32  &&
            $3.type != T_BOOL)
            yyerror("operands in and must be integer or bool\n");

        CODEGEN("iand\n");

        $$.type = $1.type;
    }
    | shift_expression {
        $$.type = $1.type;
    }
;

shift_expression
    : shift_expression LSHIFT additive_expression {
        if ($1.type != T_I32 && $3.type != T_I32)
            yyerror("operands in shift must be integer\n");

        CODEGEN("ishl\n");

        $$.type = T_I32;
    }
    | shift_expression RSHIFT additive_expression {
        if ($1.type != T_I32 && $3.type != T_I32)
            yyerror("operands in shift must be integer\n");

        CODEGEN("ishr\n");

        $$.type = T_I32;
    }
    | additive_expression {
        $$.type = $1.type;
    }
;

additive_expression
    : additive_expression '+' multiplicative_expression {
        if ($1.type != $3.type) {
            printf("first is %d, second is %d\n", $1.type, $3.type);
            yyerror("operand must in same type in addition\n");
        }

        if ($1.type == T_I32)
            CODEGEN("iadd\n");
        else if ($1.type == T_F32)
            CODEGEN("fadd\n");
        else
            yyerror("type not support in addition\n");

        $$.type = $1.type;
    }
    | additive_expression '-' multiplicative_expression {
        if ($1.type != $3.type)
            yyerror("operand must in same type in substraction\n");

        if ($1.type == T_I32)
            CODEGEN("isub\n");
        else if ($1.type == T_F32)
            CODEGEN("fsub\n");
        else
            yyerror("type not support in substraction\n");

        $$.type = $1.type;
    }
    | multiplicative_expression {
        $$.type = $1.type;
    }
;

multiplicative_expression
    : multiplicative_expression '*' casting_expression {
        if ($1.type != $3.type)
            yyerror("operand must in same type in multiplication\n");

        if ($1.type == T_I32)
            CODEGEN("imul\n");
        else if ($1.type == T_F32)
            CODEGEN("fmul\n");
        else
            yyerror("type not support in multiplication\n");

        $$.type = $1.type;
    }
    | multiplicative_expression '/' casting_expression {
        if ($1.type != $3.type)
            yyerror("operand must in same type in division\n");

        if ($1.type == T_I32)
            CODEGEN("idiv\n");
        else if ($1.type == T_F32)
            CODEGEN("fdiv\n");
        else
            yyerror("type not support in division\n");

        $$.type = $1.type;
    }
    | multiplicative_expression '%' casting_expression {
        if ($1.type != $3.type)
            yyerror("operand must in same type in reminder\n");

        if ($1.type == T_I32)
            CODEGEN("irem\n");
        else if ($1.type == T_F32)
            CODEGEN("frem\n");
        else
            yyerror("type not support in reminder\n");

        $$.type = $1.type;
    }
    | casting_expression {
        $$.type = $1.type;
    }
;

casting_expression
    : primary_expression AS type {
        if ($1.type == $3.type)
            $$.type = $1.type;
        else if ($1.type == T_I32 && $3.type == T_F32) {
            CODEGEN("i2f\n");
            $$.type = T_F32;
        }
        else if ($1.type == T_F32 && $3.type == T_I32) {
            CODEGEN("f2i\n");
            $$.type = T_I32;
        }
        else
            yyerror("casting error\n");
    }
    | unary_expression {
        $$.type = $1.type;
    }
;

unary_expression
    : '!' unary_expression {
        if ($2.type != T_I32 && $2.type != T_BOOL)
            yyerror("! must followed by integer or bool\n");
        
        if ($2.type == T_I32)
            CODEGEN("ldc %d\n", 0xFFFFFFFF);
        else
            CODEGEN("ldc 1\n");

        CODEGEN("ixor\n");

        $$.type = $2.type;
    }
    | '&' unary_expression {
        $$.type = T_ARRAY_1D;
    }
    | '-' unary_expression {
        if ($2.type != T_I32 && $2.type != T_F32)
            yyerror("- must followed by integer or float\n");
        
        if ($2.type == T_I32)
            CODEGEN("ldc 0\n");
        else
            CODEGEN("ldc 0.0\n");

        CODEGEN("swap\n");

        if ($2.type == T_I32)
            CODEGEN("isub\n");
        else
            CODEGEN("fsub\n");

        $$.type = $2.type;
    }
    | postfix_expression {
        $$.type = $1.type;
    }
;

postfix_expression
    : ID '(' ')' { /* function call */
        struct symbol *sym = lookup_symbol($1.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $1.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        CODEGEN("invokestatic Main/%s%s\n", sym->name, sym->func_sig);

        char ret_type;
        ret_type = sym->func_sig[strlen(sym->func_sig - 1)];

        if (ret_type == 'V')
            $$.type = T_VOID;
        else if (ret_type == 'I')
            $$.type = T_I32;
        else if (ret_type == 'F')
            $$.type = T_F32;
        else if (ret_type == 'B')
            $$.type = T_BOOL;
        else if (ret_type == 'L')
            $$.type = T_STR;
        else
            yyerror("return type not recognized\n");
    }
    | ID '(' argument_list ')' { /* function call with parameters */
        struct symbol *sym = lookup_symbol($1.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $1.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        /* parameters should have been on the stack */

        CODEGEN("invokestatic Main/%s%s\n", sym->name, sym->func_sig);

        char ret_type;
        ret_type = sym->func_sig[strlen(sym->func_sig - 1)];

        if (ret_type == 'V')
            $$.type = T_VOID;
        else if (ret_type == 'I')
            $$.type = T_I32;
        else if (ret_type == 'F')
            $$.type = T_F32;
        else if (ret_type == 'B')
            $$.type = T_BOOL;
        else if (ret_type == 'L')
            $$.type = T_STR;
        else
            yyerror("return type not recognized\n");
    }
    | PRINTLN '(' expression ')' { /* we only support i32, f32, bool, str */
        CODEGEN("getstatic java/lang/System/out Ljava/io/PrintStream;\n");

        if ($3.type == T_I32) {
            CODEGEN("swap\n");
            CODEGEN("invokevirtual java/io/PrintStream/println(I)V\n"); 
        } else if ($3.type == T_F32) {
            CODEGEN("swap\n");
            CODEGEN("invokevirtual java/io/PrintStream/println(F)V\n"); 
        } else if ($3.type == T_BOOL) {
            CODEGEN("swap\n");
            CODEGEN("invokevirtual java/io/PrintStream/println(Z)V\n");
        } else if ($3.type == T_STR) {
            CODEGEN("swap\n");
            CODEGEN("invokevirtual java/io/PrintStream/println(Ljava/lang/String;)V\n"); 
        } else {
            yyerror("internal error\n");
        }

        $$.type = T_VOID;
    }
    | PRINT '(' expression ')' {
        CODEGEN("getstatic java/lang/System/out Ljava/io/PrintStream;\n");

        if ($3.type == T_I32) {
            CODEGEN("swap\n");
            CODEGEN("invokevirtual java/io/PrintStream/print(I)V\n"); 
        } else if ($3.type == T_F32) {
            CODEGEN("swap\n");
            CODEGEN("invokevirtual java/io/PrintStream/print(F)V\n"); 
        } else if ($3.type == T_BOOL) {
            CODEGEN("swap\n");
            CODEGEN("invokevirtual java/io/PrintStream/print(Z)V\n");
        } else if ($3.type == T_STR) {
            CODEGEN("swap\n");
            CODEGEN("invokevirtual java/io/PrintStream/print(Ljava/lang/String;)V\n"); 
        } else {
            yyerror("internal error\n");
        }

        $$.type = T_VOID;
    }
    | ID '[' expression ']' {
        if ($3.type != T_I32)
            yyerror("Value in bracket must be integer\n");

        struct symbol *sym = lookup_symbol($1.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $1.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        if (sym->type != T_ARRAY_1D)
            yyerror("Bracket with not array type\n");

        CODEGEN("aload %d\n", sym->addr);
        CODEGEN("swap\n");

        CODEGEN("iaload\n");

        $$.type = T_I32;
    }
    | primary_expression {
        $$.type = $1.type;
    }
;

primary_expression
    : ID {
        struct symbol *sym = lookup_symbol($1.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $1.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        int local_addr = sym->addr;

        if (sym->type == T_I32 || sym->type == T_BOOL)
            CODEGEN("iload %d\n", local_addr);
        else if (sym->type == T_F32)
            CODEGEN("fload %d\n", local_addr);
        else if (sym->type == T_ARRAY_1D || sym->type == T_STR)
            CODEGEN("aload %d\n", local_addr);
        else
            yyerror("This type cannot be put on stack\n");

        $$.type = sym->type;
    }
    | literal {
        if ($1.type == T_I32 || $1.type == T_BOOL)
            CODEGEN("ldc %d\n", $1.u_val.i_val);
        else if ($1.type == T_F32)
            CODEGEN("ldc %f\n", $1.u_val.f_val);
        else if ($1.type == T_STR)
            CODEGEN("ldc \"%s\"\n", $1.u_val.s_val);
        else
            yyerror("internal error\n");

        $$.type = $1.type;
    }
    | '(' expression ')' {
        $$.type = $2.type;
    }
    | LOOP {
        g_indent_cnt = 0;
        CODEGEN("l_loop_%d:\n", loop_label);
        g_indent_cnt = 1;

        in_what_loop = IN_LOOP;
    } compound_statement_function {
        CODEGEN("goto l_loop_%d\n", loop_label);

        g_indent_cnt = 0;
        CODEGEN("l_loop_finish_%d:\n", loop_label);
        g_indent_cnt = 1;
        
        loop_label++;
        in_what_loop = NONE;

        $$.type = break_ret_type;
    }
    | array_initializer_1d {
        $$.type = T_ARRAY_1D;
    }
;

array_initializer_1d
    : '[' int_list ']' {
        $$.type = T_ARRAY_1D;
    }
;

int_list
    : int_list ',' INT_LIT {
        tmp_1d_array[array_count++] = $3.u_val.i_val;
    }
    | INT_LIT {
        tmp_1d_array[array_count++] = $1.u_val.i_val;
    }
;

literal
    : INT_LIT               { $$.u_val.i_val = $1.u_val.i_val; $$.type = T_I32; }
    | FLOAT_LIT             { $$.u_val.f_val = $1.u_val.f_val; $$.type = T_F32; }
    | '"' STRING_LIT '"'    { $$.u_val.s_val = $2.u_val.s_val; $$.type = T_STR; }
    | '"' '"'               { $$.u_val.s_val = ""; $$.type = T_STR; }
    | TRUE                  { $$.u_val.i_val = 1; $$.type = T_BOOL; }
    | FALSE                 { $$.u_val.i_val = 0; $$.type = T_BOOL; }
;

function_definition
    : FUNC ID '(' ')' {
        char *func_sig = (char *) malloc(sizeof(char) * FUNC_SIG_LEN);
        int i = 0;

        func_sig[i++] = '(';
        func_sig[i++] = type_table_simple[T_VOID];
        func_sig[i++] = ')';
        func_sig[i++] = type_table_simple[T_VOID];
        func_sig[i] = '\0';

        addr = -1;

        insert_symbol($2.u_val.s_val, -1, T_FUNC, yylineno, func_sig, 0);

        CODEGEN(".method public static ");

        /* check whether is main function */
        if (!strcmp($2.u_val.s_val, "main")) {
            CODEGEN("main([Ljava/lang/String;)V\n");
        } else {
            CODEGEN("%s()V\n", $2.u_val.s_val);
        }

        CODEGEN(".limit stack 100\n");
        CODEGEN(".limit locals 100\n");

        g_indent_cnt = 1;
    } compound_statement_function {
        CODEGEN("return\n");
        CODEGEN(".end method\n");
    }
    | FUNC ID '(' ')' ARROW type {
        char *func_sig = (char *) malloc(sizeof(char) * FUNC_SIG_LEN);
        int i = 0;

        func_sig[i++] = '(';
        func_sig[i++] = type_table_simple[T_VOID];
        func_sig[i++] = ')';
        func_sig[i++] = type_table_simple[$6.type];
        func_sig[i] = '\0';

        addr = -1;

        insert_symbol($2.u_val.s_val, -1, T_FUNC, yylineno, func_sig, 0);

        CODEGEN(".method public static %s()%c\n", $2.u_val.s_val, 
            type_table_simple[$6.type]);

        CODEGEN(".limit stack 100\n");
        CODEGEN(".limit locals 100\n");

        g_indent_cnt = 1;
    } compound_statement_function {
        if ($6.type == T_I32 || $6.type == T_BOOL)
            CODEGEN("ireturn\n");
        else if ($6.type == T_F32)
            CODEGEN("freturn\n");
        else if ($6.type == T_STR)
            CODEGEN("areturn\n");
        else
            yyerror("not supported return type\n");

        CODEGEN(".end method\n");
    }
    | FUNC ID '(' parameter_list ')' {
        char *func_sig = (char *) malloc(sizeof(char) * FUNC_SIG_LEN);
        int i = 0;

        func_sig[i++] = '(';
        for (int j = 0; j < fp_count; j++)
            func_sig[i++] = type_table_simple[$4.fp[j].fp_type];
        func_sig[i++] = ')';
        func_sig[i++] = type_table_simple[T_VOID];
        func_sig[i] = '\0';

        addr = -1;

        insert_symbol($2.u_val.s_val, -1, T_FUNC, yylineno, func_sig, 0);
        
        /* for every parameter */
        for (int i = 0; i < fp_count; i++)
            insert_symbol($4.fp[i].fp_name, 0, $4.fp[i].fp_type,
                yylineno, NULL, 0);

        fp_count = 0;

        CODEGEN(".method public static %s(", $2.u_val.s_val);
        for (int i = 0; i < fp_count; i++)
            CODEGEN("%c", type_table_simple[$4.fp[i].fp_type]);
        CODEGEN(")\n");

        CODEGEN(".limit stack 100\n");
        CODEGEN(".limit locals 100\n");
    } compound_statement_function {
        CODEGEN("return\n");
        CODEGEN(".end method\n");
    }
    | FUNC ID '(' parameter_list ')' ARROW type {
        char *func_sig = (char *) malloc(sizeof(char) * FUNC_SIG_LEN);
        int i = 0;

        func_sig[i++] = '(';
        for (int j = 0; j < fp_count; j++)
            func_sig[i++] = type_table_simple[$4.fp[j].fp_type];
        func_sig[i++] = ')';
        func_sig[i++] = type_table_simple[$7.type];
        func_sig[i] = '\0';

        addr = -1;

        insert_symbol($2.u_val.s_val, -1, T_FUNC, yylineno, func_sig, 0);
        
        /* for every parameter */
        for (int i = 0; i < fp_count; i++)
            insert_symbol($4.fp[i].fp_name, 0, $4.fp[i].fp_type,
                yylineno, NULL, 0);

        fp_count = 0;

        CODEGEN(".method public static %s(", $2.u_val.s_val);
        for (int i = 0; i < fp_count; i++)
            CODEGEN("%c", $4.fp[i].fp_type);
        CODEGEN(")%c\n", $7.type);

        CODEGEN(".limit stack 100\n");
        CODEGEN(".limit locals 100\n");

        g_indent_cnt = 1;
    } compound_statement_function {
        if ($7.type == T_I32 || $7.type == T_BOOL)
            CODEGEN("ireturn\n");
        else if ($7.type == T_F32)
            CODEGEN("freturn\n");
        else if ($7.type == T_STR)
            CODEGEN("areturn\n");
        else
            yyerror("not supported return type\n");

        CODEGEN(".end method\n");
    }
;

argument_list /* for now, we can just pass i32, f32 and bool */
    : argument_list ',' ID {
        if ($3.type == T_I32 || $3.type == T_BOOL)
            CODEGEN("ldc %d\n", $3.u_val.i_val);
        else
            CODEGEN("ldc %f\n", $3.u_val.f_val);
    }
    | ID {
        if ($1.type == T_I32 || $1.type == T_BOOL)
            CODEGEN("ldc %d\n", $1.u_val.i_val);
        else
            CODEGEN("ldc %f\n", $1.u_val.f_val);
    }
;

parameter_list
    : parameter_list ',' name_type      {
        $$.fp[fp_count].fp_name = $3.u_val.s_val;
        $$.fp[fp_count].fp_type = $3.type;
        fp_count++;
    }
    | name_type                         {
        $$.fp[fp_count].fp_name = $1.u_val.s_val;
        $$.fp[fp_count].fp_type = $1.type;
        fp_count++;
    }
;

compound_statement
    : '{' {
        create_symbol_table();
    } declaration_or_statement_list '}' {
        dump_symbol();
    }
;

compound_statement_function
    : '{' { 
        create_symbol_table(); 
    } declaration_or_statement_list '}' {
        dump_symbol();
    }
    | '{' {
        create_symbol_table();
    } declaration_or_statement_list expression '}' {
        $$.type = $4.type;

        dump_symbol();
    }
    | '{' {
        create_symbol_table();
    } expression '}' {
        $$.type = $3.type;

        dump_symbol();
    }

declaration_or_statement_list
    : declaration_or_statement_list declaration_or_statement
    | declaration_or_statement
;

declaration_or_statement
    : declaration
    | statement
;

statement_list
    : statement_list statement
    | statement
;

statement
    : compound_statement
    | expression_statement
    | selection_statement
    | iteration_statement
    | jump_statement
;

expression_statement
    : expression ';'
    | ';'
;

selection_statement
    : IF expression {
        CODEGEN("ldc 0\n");
        CODEGEN("if_icmpne l_if_success_%d\n", if_label);
        CODEGEN("goto l_if_else_%d\n", if_label);
        g_indent_cnt = 0;
        CODEGEN("l_if_success_%d:\n", if_label);
        g_indent_cnt = 1;
    } statement {
        CODEGEN("goto l_if_finish_%d\n", if_label);
    } else_statement
;

else_statement
    : ELSE {
        g_indent_cnt = 0;
        CODEGEN("l_if_else_%d:\n", if_label);
        g_indent_cnt = 1;
    } statement {
        g_indent_cnt = 0;
        CODEGEN("l_if_finish_%d:\n", if_label);
        g_indent_cnt = 1;

        if_label++;
    }
    | {
        g_indent_cnt = 0;
        CODEGEN("l_if_else_%d:\n", if_label);
        CODEGEN("l_if_finish_%d:\n", if_label);
        g_indent_cnt = 1;

        if_label++;
    }
;

iteration_statement
    : FOR ID IN ID {
        struct symbol *sym = lookup_symbol($4.u_val.s_val);
        if (sym == NULL) {
            printf("line %d: symbol %s is not declared\n", 
                yylineno, $4.u_val.s_val);

            yyerror("symbol not declared");
            return 1;
        }

        if (sym->type != T_ARRAY_1D)
            yyerror("for each must be with array\n");

        create_symbol_table();

        int arr_addr = sym->addr;
        int local_addr = addr;
        int count = sym->len;

        insert_symbol($2.u_val.s_val, 0, T_I32,
                yylineno, NULL, 0);

        CODEGEN("ldc %d\n", count); // boundary
        CODEGEN("ldc 0\n");         // counter
        g_indent_cnt = 0;
        CODEGEN("l_for_%d:\n", for_label);
        g_indent_cnt = 1;
        CODEGEN("dup2\n");
        CODEGEN("if_icmpeq l_for_finish_%d\n", for_label);
        CODEGEN("dup\n");
        CODEGEN("aload %d\n", arr_addr);
        CODEGEN("swap\n");
        CODEGEN("iaload\n");
        CODEGEN("istore %d\n", local_addr);

        in_what_loop = IN_FOR;
    } statement {
        CODEGEN("ldc 1\n");
        CODEGEN("iadd\n");
        CODEGEN("goto l_for_%d\n", for_label);
        g_indent_cnt = 0;
        CODEGEN("l_for_finish_%d:\n", for_label);
        g_indent_cnt = 1;
        CODEGEN("pop2\n");

        in_what_loop = NONE;

        for_label++;

        dump_symbol();
    }
    | WHILE {
        g_indent_cnt = 0;
        CODEGEN("l_while_%d:\n", while_label);
        g_indent_cnt = 1;

        in_what_loop = IN_WHILE;
    }
    expression {
        CODEGEN("ldc 0\n");
        CODEGEN("if_icmpeq l_while_finish_%d\n", while_label);
    } statement {
        CODEGEN("goto l_while_%d\n", while_label);
        g_indent_cnt = 0;
        CODEGEN("l_while_finish_%d:\n", while_label);
        g_indent_cnt = 1;

        in_what_loop = NONE;

        while_label++;
    }
;

jump_statement
    : BREAK ';' {
        if (in_what_loop == NONE)
            yyerror("not in loop\n");
        else if (in_what_loop == IN_LOOP)
            CODEGEN("goto l_loop_finish_%d\n", loop_label);
        else if (in_what_loop == IN_FOR)
            CODEGEN("goto l_for_finish_%d\n", for_label);
        else
            CODEGEN("goto l_while_finish_%d\n", while_label);
    }
    | BREAK expression ';' {
        if (in_what_loop == NONE)
            yyerror("not in loop\n");
        else if (in_what_loop == IN_LOOP)
            CODEGEN("goto l_loop_finish_%d\n", loop_label);
        else if (in_what_loop == IN_FOR)
            CODEGEN("goto l_for_finish_%d\n", for_label);
        else
            CODEGEN("goto l_while_finish_%d\n", while_label);

        break_ret_type = $2.type;
    }
    | RETURN ';' {
        CODEGEN("return");
    }
    | RETURN expression ';' {
        if ($2.type == T_I32)
            CODEGEN("ireturn");
        else if ($2.type == T_F32)
            CODEGEN("freturn");
        else if ($2.type == T_STR)
            CODEGEN("areturn");
        else
            yyerror("return type not supported\n");

        break_ret_type = $2.type;
    }
;

%%

/* C code section */
int main(int argc, char *argv[])
{
    if (argc == 2) {
        yyin = fopen(argv[1], "r");
    } else {
        yyin = stdin;
    }
    if (!yyin) {
        printf("file `%s` doesn't exists or cannot be opened\n", argv[1]);
        exit(1);
    }

    /* Codegen output init */
    char *bytecode_filename = "hw3.j";
    fout = fopen(bytecode_filename, "w");
    CODEGEN(".source hw3.j\n");
    CODEGEN(".class public Main\n");
    CODEGEN(".super java/lang/Object\n");

    /* Symbol table init */
    // Add your code

    init_symbol_table();
    create_symbol_table();

    yylineno = 0;
    yyparse();

    dump_symbol();

    /* Symbol table dump */
    // Add your code

	printf("Total lines: %d\n", yylineno);

    fclose(fout);
    fclose(yyin);

    if (g_has_error) {
        remove(bytecode_filename);
    }
    yylex_destroy();
    return 0;
}

static void init_symbol_table() {
    memset(symbol_table, 0, 
        sizeof(struct symbol) * SYM_TABLE_ROW * SYM_TABLE_COL);
    memset(symbol_table_idx, 0, sizeof(int) * SYM_TABLE_ROW);
}

static void create_symbol_table() {
    global_scope++;
    symbol_table_idx[global_scope] = 0;

    printf("> Create symbol table (scope level %d)\n", global_scope);
}

static void insert_symbol(char *name, int mut, int type, 
                            int lineno, char *func_sig, int len) {
    printf("> Insert `%s` (addr: %d) to scope level %d\n", name, addr, 
                                                        global_scope);
    int cur_tab_idx = symbol_table_idx[global_scope];
    symbol_table[global_scope][cur_tab_idx] = 
    (struct symbol) {
        .index = cur_tab_idx,
        .name = name,
        .mut = mut,
        .type = type,
        .addr = addr,
        .lineno = lineno,
        .func_sig = func_sig,
        .len = len
    };

    addr++;
    symbol_table_idx[global_scope]++;
}

static struct symbol *lookup_symbol(char *name) {
    for (int i = global_scope; i >= 0; i--) {
        for (int j = 0; j < SYM_TABLE_COL; j++) {
            if (name == NULL || symbol_table[i][j].name == NULL)
                break;

            if (!strcmp(symbol_table[i][j].name, name))
                return &symbol_table[i][j];
        }
    }
    return NULL;
}

/* After calling dump_symbol, the current symbol table will be dropped */
static void dump_symbol() {
    printf("\n> Dump symbol table (scope level: %d)\n", global_scope);
    printf("%-10s%-10s%-10s%-10s%-10s%-10s%-10s\n",
        "Index", "Name", "Mut","Type", "Addr", "Lineno", "Func_sig");

    for (int i = 0; i < SYM_TABLE_COL; i++) {
        struct symbol *cur = &symbol_table[global_scope][i];

        if (cur->name == NULL)
            break;

        printf("%-10d%-10s%-10d%-10s%-10d%-10d%-10s\n",
            cur->index, cur->name, cur->mut, type_table[cur->type], 
            cur->addr, cur->lineno, cur->func_sig ? cur->func_sig : "-");

        cur->name = NULL;
    }

    symbol_table_idx[global_scope] = 0;
    global_scope--;
}
