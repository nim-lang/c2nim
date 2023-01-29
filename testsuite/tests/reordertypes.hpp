#pragma c2nim reordertypes

class foo{
public:
  operator int () const {return val;}
  int val;
};

class bar{
public:
  int operator + (int b) {return val+b;}
  int val;
};