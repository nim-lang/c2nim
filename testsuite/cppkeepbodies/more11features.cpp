
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

// bug #190

#def Q_DISABLE_COPY(MyClass) \
    MyClass(const MyClass &) = delete; \
    MyClass &operator=(const MyClass &) = delete;

#define Q_CORE_EXPORT

class Q_CORE_EXPORT QObjectData
{
    Q_DISABLE_COPY(QObjectData)
public:
    QObjectData() = default;
    virtual ~QObjectData() = 0;
    QObject *q_ptr;
    QObject *parent;
    QObjectList children;

    uint isWidget : 1;
    uint blockSig : 1;
    uint wasDeleted : 1;
    uint isDeletingChildren : 1;
    uint sendChildEvents : 1;
    uint receiveChildEvents : 1;
    uint isWindow : 1; // for QWindow
    uint deleteLaterCalled : 1;
    uint unused : 24;
    int postedEvents;
    QDynamicMetaObjectData *metaObject;
    QBindingStorage bindingStorage;
    QMetaObject *dynamicMetaObject() const override final;
};

// C++ lambdas

auto ex1 = [] (int x) { std::cout << x << '\n'; };

auto ex2 = [] ()   { code; };

auto ex3 = [](float f, int a) { return a*f; };
auto ex4 = [](MyClass t) -> int { auto a = t.compute(); return a; };
auto ex5 = [](int a, int b) { return a < b; };

auto myLambda = [](int a) -> double { return 2.0 * a; };

auto myLambda = [](int a) mutable { std::cout << a; };

auto baz = [] () {
    int x = 10;
    if ( x < 20)
        return x * 1.1;
    else
        return x * 2.1;
};

int x = 1, y = 1;
[&]() { ++x; ++y; }(); // <-- call ()


int main() {
    int x = 10;
    int y = 11;
    // Captures With an Initializer
    auto foo = [z = x+y]() { std::cout << z << '\n'; };
    foo();

    std::unique_ptr<int> p(new int{10});
    auto foo = [x=10] () mutable { ++x; };
    auto bar = [ptr=std::move(p)] {};
    auto baz = [p=std::move(p)] {};
}

// decltype
int i;

decltype(i+3) j;

typedef std::function<void(void)> Foo;

// bug #78
for (int i = 0; i < 44; i++) {
  if (a[i]) continue;
  print(a[i]);
}

// smart def vs define heuristic:
#define for_each(x) for(int i = 0; i < x; ++i)

#define other(x) for(int i = 0; i < x; ++i) printf(i);

template <typename T>
class Foo {
public:
        Foo(){
          for_each(89) printf(i);
          other(13);

        };
};

// bug #59

enum class Color { red, green = 20, blue };

class MyClass {
  Color color;
public:
  void (*warning)(const char*, ...);    // <- this fails!!
  void *warning(const char*, ...);


  T&       value() &;
  T&&      value() &&;
  T const& value() const&;
};

void* MyClass::warning(const char*, ...) {
  int bodyHere;
  switch (this->color) {
    using enum Color;
    case red: ;
    case green:
      bodyHere = 123;
    case blue: ;
  }

  if (auto f = (5+6); f != 0) {
    printf("I love syntactic sugar!\n");
  }
}
