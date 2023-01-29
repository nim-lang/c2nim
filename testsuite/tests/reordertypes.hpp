#pragma c2nim reordertypes

class foo{
public:
  operator int () const {return val;}
  int val;
  enum { F1 = 33 };
};

class bar{
public:
  int operator + (int b) {return val+b;}
  int val;
  enum { B1 = 44 };
};