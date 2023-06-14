/* Please feel free to modify any content */

/* Definition section */
%{
    #include "compiler_common.h" //Extern variables that communicate with lex
    // #define YYDEBUG 1
    // int yydebug = 1;

    extern int yylineno;
    extern int yylex();
    extern FILE *yyin;

    int yylex_destroy ();
    void yyerror (char const *s)
    {
        printf("error:%d: %s\n", yylineno, s);
    }

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
    static void insert_symbol(char *name, bool mut, const char *type, 
                            int lineno, char *func_sig);
    static bool lookup_symbol(char *name);
    static void dump_symbol();

    /* Global variables */
    bool g_has_error = false;
    FILE *fout = NULL;
    int g_indent_cnt = 0;

    struct symbol {
        int index;
        char *name;
        bool mut;
        const char *type;
        int addr;
        int lineno;
        char *func_sig;
    };

    static int fp_count = 0;

    #define SYM_TABLE_ROW 6
    #define SYM_TABLE_COL 16
    static struct symbol symbol_table[SYM_TABLE_ROW][SYM_TABLE_COL];

    static int global_scope = -1, global_addr = -1;
    static int cur_tab_idx = 0;

    static const char *type_table[] = {
        "i32",
        "f32",
        "bool",
        "str",
        "array",
        "void"
    };

    static const char type_table_simple[] = {
        'I',
        'F',
        'B',
        'S',
        'A',
        'V'
    };

    #define FUNC_SIG_LEN 16

    enum types {
    T_I32,
    T_F32,
    T_BOOL,
    T_STR,
    T_ARRAY,
    T_VOID
};
%}

%error-verbose

/* Use variable or self-defined structure to represent
 * nonterminal and token type
 *  - you can add new fields if needed.
 */
%union {
    struct {
        union {
            int i_val;
            float f_val;
            char *s_val;
        } u_val;
        int type;
        struct func_param {
            char *fp_names;
            int fp_types;
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
        insert_symbol($2.u_val.s_val, 0, type_table[$2.type], yylineno, NULL);
    }
    | LET MUT name_type '=' expression ';' {
        insert_symbol($3.u_val.s_val, 1, type_table[$3.type], yylineno, NULL);
    }
    | LET name_type ';' {
        insert_symbol($2.u_val.s_val, 0, type_table[$2.type], yylineno, NULL);
    }
    | LET MUT name_type ';' {
        insert_symbol($3.u_val.s_val, 1, type_table[$3.type], yylineno, NULL);
    }
;

name_type
    : ID            { $$.u_val.s_val = $1.u_val.s_val; }
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
    | array_type    { $$.type = T_ARRAY; }
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
    : assignment_expression
;

assignment_expression
    : unary_expression assignment_operator assignment_expression
    | range_expression
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
    : INT_LIT DOTDOT
    | DOTDOT INT_LIT
    | INT_LIT DOTDOT INT_LIT
    | logical_or_expression
;

logical_or_expression
    : logical_or_expression LOR logical_and_expression
    | logical_and_expression
;

logical_and_expression
    : logical_and_expression LAND rational_expression
    | rational_expression
;

rational_expression
    : rational_expression rational_operator inclusive_or_expression
    | inclusive_or_expression
;

rational_operator
    : GEQ
    | LEQ
    | EQL
    | NEQ
    | '>'
    | '<'
;

inclusive_or_expression
    : inclusive_or_expression '|' exclusive_or_expression
    | exclusive_or_expression
;

exclusive_or_expression
    : exclusive_or_expression '^' and_expression
    | and_expression
;

and_expression
    : and_expression '&' shift_expression
    | shift_expression
;

shift_expression
    : shift_expression LSHIFT additive_expression
    | shift_expression RSHIFT additive_expression
    | additive_expression
;

additive_expression
    : additive_expression '+' multiplicative_expression
    | additive_expression '-' multiplicative_expression
    | multiplicative_expression
;

multiplicative_expression
    : multiplicative_expression '*' casting_expression
    | multiplicative_expression '/' casting_expression
    | multiplicative_expression '%' casting_expression
    | casting_expression
;

casting_expression
    : expression AS type
    | unary_expression
;

unary_expression
    : unary_operator unary_expression
    | postfix_expression
;

unary_operator
    : '!'
    | '&'
    | '-'
;

postfix_expression
    : postfix_expression '(' ')'
    | postfix_expression '(' argument_list ')'
    | PRINTLN '(' expression ')'                { printf("PRINTLN str\n"); }
    | PRINT '(' expression ')'
    | postfix_expression '[' expression ']'
    | primary_expression
;

primary_expression
    : ID
    | literal
    | '(' expression ')'
    | LOOP statement
    | array_initializer_1d
    | array_initializer_all
;

array_initializer_1d
    : '[' literal_list ']'
;

literal_list
    : literal_list ',' literal
    | literal
;

literal
    : INT_LIT               { printf("INT_LIT %d\n", $1.u_val.i_val); }
    | FLOAT_LIT             { printf("FLOAT_LIT %f\n", $1.u_val.f_val); }
    | '"' STRING_LIT '"'    { printf("STRING_LIT \"%s\"\n", $2.u_val.s_val); }
    | '"' '"'               { printf("STRING_LIT \"\"\n"); }
    | TRUE                  { printf("bool TRUE\n"); }
    | FALSE                 { printf("bool FALSE\n"); }
;

array_initializer_all
    : '[' array_initializer_all ';' INT_LIT ']'
    | literal
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

        insert_symbol($2.u_val.s_val, -1, "func", yylineno, func_sig);
    } compound_statement_function
    | FUNC ID '(' ')' ARROW type {
        char *func_sig = (char *) malloc(sizeof(char) * FUNC_SIG_LEN);
        int i = 0;

        func_sig[i++] = '(';
        func_sig[i++] = type_table_simple[T_VOID];
        func_sig[i++] = ')';
        func_sig[i++] = type_table_simple[$6.type];
        func_sig[i] = '\0';

        insert_symbol($2.u_val.s_val, -1, "func", yylineno, func_sig);
    } compound_statement_function
    | FUNC ID '(' parameter_list ')' {
        char *func_sig = (char *) malloc(sizeof(char) * FUNC_SIG_LEN);
        int i = 0;

        func_sig[i++] = '(';
        for (int j = 0; j < fp_count; j++)
            func_sig[i++] = type_table_simple[$4.fp[j].fp_types];
        func_sig[i++] = ')';
        func_sig[i++] = type_table_simple[T_VOID];
        func_sig[i] = '\0';

        insert_symbol($2.u_val.s_val, -1, "func", yylineno, func_sig);
        
        /* for every parameter */
        for (int i = 0; i < fp_count; i++)
            insert_symbol($4.fp[i].fp_names, 0, type_table[$4.fp[i].fp_types],
                yylineno, NULL);

        fp_count = 0;
    } compound_statement_function 
    | FUNC ID '(' parameter_list ')' ARROW type {
        char *func_sig = (char *) malloc(sizeof(char) * FUNC_SIG_LEN);
        int i = 0;

        func_sig[i++] = '(';
        for (int j = 0; j < fp_count; j++)
            func_sig[i++] = type_table_simple[$4.fp[j].fp_types];
        func_sig[i++] = ')';
        func_sig[i++] = type_table_simple[$7.type];
        func_sig[i] = '\0';

        insert_symbol($2.u_val.s_val, -1, "func", yylineno, func_sig);
        
        /* for every parameter */
        for (int i = 0; i < fp_count; i++)
            insert_symbol($4.fp[i].fp_names, 0, type_table[$4.fp[i].fp_types],
                yylineno, NULL);

        fp_count = 0;
    } compound_statement_function
;

argument_list
    : argument_list ',' expression
    | expression
;

parameter_list
    : parameter_list ',' name_type      {
        $$.fp[fp_count].fp_names = $3.u_val.s_val;
        $$.fp[fp_count].fp_types = $3.type;
        fp_count++;
    }
    | name_type                         {
        $$.fp[fp_count].fp_names = $1.u_val.s_val;
        $$.fp[fp_count].fp_types = $1.type;
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
        dump_symbol();
    }
    | '{' {
        create_symbol_table();
    } expression '}' {
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
    : IF expression statement
    | IF expression statement ELSE statement
;

iteration_statement
    : LOOP statement
    | FOR ID IN ID statement
    | WHILE expression statement
;

jump_statement
    : BREAK ';'
    | BREAK expression ';'
    | RETURN ';'
    | RETURN expression ';'
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

    yylineno = 0;
    yyparse();

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
}

static void create_symbol_table() {
    global_scope++;
    cur_tab_idx = 0;

    printf("> Create symbol table (scope level %d)\n", global_scope);
}

static void insert_symbol(char *name, bool mut, const char *type, 
                            int lineno, char *func_sig) {
    printf("> Insert `%s` (addr: %d) to scope level %d\n", name, global_addr, 
                                                        global_scope);
    symbol_table[global_scope][cur_tab_idx] = 
    (struct symbol) {
        .index = cur_tab_idx,
        .name = name,
        .mut = mut,
        .type = type,
        .addr = global_addr,
        .lineno = lineno,
        .func_sig = func_sig,
    };

    global_addr++;
    cur_tab_idx++;
}

static bool lookup_symbol(char *name) {
    for (int i = global_scope; i >= 0; i--) {
        for (int j = 0; j < SYM_TABLE_COL; j++) {
            if (name == NULL)
                break;

            if (!strcmp(symbol_table[i][j].name, name))
                return true;
        }
    }
    return false;
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
            cur->index, cur->name, cur->mut, cur->type, 
            cur->addr, cur->lineno, cur->func_sig ? cur->func_sig : "-");

        cur->name = NULL;
    }

    global_scope--;
    cur_tab_idx = 0;
}
