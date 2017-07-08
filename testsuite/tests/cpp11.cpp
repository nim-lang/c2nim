class Event
{
public:
  Event() = default;
};

std::ostream &operator << (std::ostream &out, const Enum &t);
