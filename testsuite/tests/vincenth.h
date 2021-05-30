struct foo {
    int x,y,z;
};

// C11 init syntax:
const foo lookup[2] = {
    [0] = {.x = 1, .y = 3, .z = 4},
    [1] = {.x = 2, .y = 3, .z = 4}
};

enum message_type {
       MESSAGE_TYPE_NOTICE,
       MESSAGE_TYPE_PRIVMSG,
       MESSAGE_TYPE_COUNT
};

const char *cmdname[MESSAGE_TYPE_COUNT] = {
    [MESSAGE_TYPE_PRIVMSG] = "PRIVMSG",
    [MESSAGE_TYPE_NOTICE] = "NOTICE",
};

#define EFI_FIRMWARE_VENDOR         L"INTEL" // line 30
#define EFI_FIRMWARE_MAJOR_REVISION 12   // line 31
#define EFI_FIRMWARE_MINOR_REVISION 33
#define EFI_FIRMWARE_REVISION ((EFI_FIRMWARE_MAJOR_REVISION <<16) | (EFI_FIRMWARE_MINOR_REVISION))
