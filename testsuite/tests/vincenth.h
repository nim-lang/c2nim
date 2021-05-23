struct foo {
    int x,y,z;
};

// C11 init syntax:
const foo lookup[2] = {
    [0] = {.x = 1, .y = 3, .z = 4},
    [1] = {.x = 2, .y = 3, .z = 4}
};
