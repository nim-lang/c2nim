class Event
{
public:
  Event() = default;
};

std::ostream &operator << (std::ostream &out, const Enum &t);

constexpr Event foo;

class ConstexprConstructor {
  public:
  constexpr ConstexprConstructor(int i = 1) : id(i) {}
};
// list initialization, issue #163
constexpr int list_init{123};
