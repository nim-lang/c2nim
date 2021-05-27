
#assumedef windows

class failClass1 {
public:
  int tmpI;
#ifdef windows
  void someProc(int x);
#else
  void* myfield;
#endif

#if 0
  int atLeastSkipThis;
#endif
};

class failClass2 {
public:
  int tmpI;
  #define myconst 122
#ifdef unknown
  void someIfdefProc(int x);
#else
  void* myfield;
#endif
};

