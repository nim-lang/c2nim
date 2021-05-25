class Event
{
public:
  Event() = default;
};

std::ostream &operator << (std::ostream &out, const Enum &t);

constexpr Event foo;

class ConstexprConstructor {
  public:
  [[deprecated("getCenter() was renamed to getResourceDepot()")]]
  constexpr ConstexprConstructor(int i = 1) : id(i) {}
};
// list initialization, issue #163
constexpr int list_init{123};

class NonCopy {
public:
  NonCopy() {}
  ~NonCopy() {}
  // deleted constructor, issue #165
  NonCopy(const NonCopy &) = delete;
  NonCopy &operator=(const NonCopy &) = delete;
};

class VirtClass {
public:
  VirtClass() = default;
  ~VirtClass() = 0;
  virtual void pureFunction() = 0;
  virtual void implementedFunction();
  void concreteFunction();
};

namespace VarNS
{
  const int my_var = 5;
}
