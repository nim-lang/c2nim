#delete "`++`*"
#cppallops

class foo{
public:
  int operator++() const {return val;}
  int val;
};