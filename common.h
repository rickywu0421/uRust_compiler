#ifndef COMMON_H
#define COMMON_H

union val_union {
    int i_val;
    float f_val;
    char *s_val;
    int *i_1d_array;
    int **i_2d_array;
};

#endif /* COMMON_H */