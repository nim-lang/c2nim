
#def static_assert(x, y)

struct Double
{
    static_assert(std::numeric_limits<double>::is_iec559
               && std::numeric_limits<double>::digits == 53
               && std::numeric_limits<double>::max_exponent == 1024,
        "IEEE-754 double-precision implementation required");

    using value_type = double;
    using bits_type = uint64_t;

    static constexpr int32_t   SignificandSize = std::numeric_limits<value_type>::digits; // = p   (includes the hidden bit)
    static constexpr int32_t   ExponentBias    = std::numeric_limits<value_type>::max_exponent - 1 + (SignificandSize - 1);
    static constexpr bits_type MaxIeeeExponent = bits_type{2 * std::numeric_limits<value_type>::max_exponent - 1};
    static constexpr bits_type HiddenBit       = bits_type{1} << (SignificandSize - 1);   // = 2^(p-1)
    static constexpr bits_type SignificandMask = HiddenBit - 1;                           // = 2^(p-1) - 1
    static constexpr bits_type ExponentMask    = MaxIeeeExponent << (SignificandSize - 1);
    static constexpr bits_type SignMask        = ~(~bits_type{0} >> 1);

    bits_type bits;

    explicit Double(bits_type bits_) : bits(bits_) {}
    explicit Double(value_type value) : bits(ReinterpretBits<bits_type>(value)) {}

};

#include <cstdint>
#include <vector>

int main(){
  std::vector<int64_t> foo(10);
  return 0;
}

#define MYIGNORE
#define MYCDECL   __cdecl

int test1() { int x = 1; return (x); }
int MYCDECL test2() { int x = 2; return (x); }

#if defined(MYIGNORE)
  int myVar;

  MYIGNORE int test3() {
    myVar = test1();
	myVar = myVar + test2();
	return(myVar);
  }

#endif

#ifdef MYIGNORE

  MYIGNORE int test4() {
    myVar = test1();
	myVar = myVar + test2();
	return(myVar);
  }

#endif

#ifdef DEBUG
#  define OUT(x) printf("%s\n", x)
#else
#  define OUT(x)
#endif

