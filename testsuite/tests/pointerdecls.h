// posix signal
void(*signal(int, void (*)(int)))(int);

// str signal
char *strsignal(int __sig);
// str signal
int strsignal_r(int __sig, char *__strsignalbuf, size_t __buflen);

// attributes
int (* _Nullable _close)(void *);
int (* _Nullable _read) (void *, char *, int);

// __attribute__
int vasprintf(char ** restrict, const char * restrict, __gnuc_va_list) __attribute__((__format__ (__printf__, 2, 0)));
void __assert_rtn(const char *, const char *, int, const char *) __attribute__((__noreturn__)) __attribute__((__cold__)) ;
void *malloc(size_t __size) __attribute__((__warn_unused_result__)) __attribute__((alloc_size(1)));

// struct attribute 
struct _OSUnalignedU16 {
 volatile uint16_t __val;
} __attribute__((__packed__));

// other typedefs
typedef long long int64_t;
typedef unsigned short uint16_t;
typedef unsigned int __uint32_t;
typedef long long __int64_t;
typedef unsigned long long __uint64_t;
typedef long unsigned int __darwin_size_t;